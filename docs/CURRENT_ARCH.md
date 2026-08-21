# CURRENT_ARCH.md — LCdrData

A snapshot of the **as-built** architecture, distinct from the intended design.

> **`DESIGN.md`** is the spec — what LCdrData is meant to become.
> **`CURRENT_ARCH.md`** (this file) is the reality — what the code on `develop` actually does today.
>
> When the two disagree, the code wins; see [§9 Divergence from DESIGN.md](#9-divergence-from-designmd).
>
> _Last updated: 2026-05-01 (branch `develop`)._

LCdrData is a native macOS dual-panel file manager built with SwiftUI on Swift 6 with strict concurrency. All types default to `@MainActor`. The app is sandboxed with user-selected read-write file access and app-scope security-scoped bookmarks. Configuration is a KDL document.

---

## 1. Top-level layout

```
LCdrData/
├── Tuist.swift                Tuist generation config
├── Project.swift              Target manifest
├── Tuist/Package.swift        SPM dependency declarations
├── .tuist-version             4.182.0 (pinned)
├── LCdrData/                  App target sources
│   ├── App/                   @main + AppDelegate
│   ├── Models/                Value types
│   ├── Services/              File I/O, sandbox, config, watching
│   ├── ViewModels/            @Observable state coordinators
│   ├── Views/                 SwiftUI presentation
│   ├── Utilities/             Formatters, key shortcuts, env keys
│   └── Resources/             DefaultConfig.kdl, Assets.xcassets
├── LCdrDataTests/             Swift Testing unit tests
└── LCdrDataUITests/           XCTest UI tests
```

The `.xcodeproj` and `.xcworkspace` are not committed; run `tuist install && tuist generate` after pulling.

---

## 2. Build & target settings

| Setting | Value |
|---|---|
| Tuist | 4.182.0 |
| Swift | 5.0 (compiler), but Swift 6 concurrency features enabled |
| Deployment target | macOS 26.4 |
| Destinations | `.mac` only |
| Bundle ID (app) | `com.xvir.LCdrData` |
| App Sandbox | enabled (`ENABLE_APP_SANDBOX=YES`) |
| User-selected files | `readwrite` |
| Bookmarks | `ENABLE_APP_SANDBOXED_FILES_BOOKMARKS_APP_SCOPE=YES` |
| Default actor isolation | `MainActor` |
| Approachable concurrency | `YES` |
| Member import visibility | `YES` |

Two test targets: `LCdrDataTests` (Swift Testing — `import Testing`, `@Test`, `#expect`) and `LCdrDataUITests` (XCTest). Per `CLAUDE.md`, only unit tests should be run during routine development.

---

## 3. Layers

### 3.1 App/ — entry point

| File | Purpose |
|---|---|
| `LCdrDataApp.swift` | `@main` struct. Creates a single `AppState`; sets up the `WindowGroup` (1100×700 default, 800×500 min); wires custom commands into File / Edit / Navigation / Favorites menus; declares the `Settings` scene that hosts `ConfigurationView`. |
| `AppDelegate.swift` | `NSApplicationDelegate`. Quits when the last window closes; on `applicationWillTerminate` calls `AppState.savePanelPaths()` and `releasePanelSecurityScope()`. |

### 3.2 Models/ — value types (all `Sendable`)

| File | Purpose |
|---|---|
| `FileItem.swift` | `struct FileItem: Identifiable, Hashable, Sendable`. Carries name, URL, sizes, dates, hidden/symlink flags, plus a synthetic `isParentDirectory` flag for the `..` row. The `id: UUID` is **deterministically derived from the URL** via SHA256 (`stableID(for:)`), which keeps SwiftUI list identity stable across reloads and avoids row flicker. `init` and the static helpers are `nonisolated`. |
| `PanelState.swift` | Per-panel state container: `currentDirectory`, `items`, `selectedItemIDs`, `focusedItemID`, `sortDescriptor`, `showHiddenFiles`, `history`, `historyIndex`. |
| `SortDescriptor.swift` | `FileSortDescriptor { Column { name, size, dateModified, dateCreated, kind }, ascending }` with `mutating func toggle(column:)` — same column flips direction, new column resets to ascending. |
| `FileOperation.swift` | `FileOperationKind` (copy / move / delete / permanentDelete / createFolder / rename), `FileOperationStatus` (pending / inProgress / completed / failed(String) / cancelled), `FileOperationProgress` (`totalItems`, `completedItems`, `currentItemName`, computed `fractionCompleted`), and the operation struct itself. |
| `AppConfiguration.swift` | Effective configuration with sane defaults (hidden off, sort by name asc, font 13pt, date format `yyyy-MM-dd HH:mm`, editor `com.apple.TextEdit`); nested `BookmarkEntry { label, path }`; computed `sortDescriptor`. |

### 3.3 Services/ — protocol-fronted I/O

All service protocols are `Sendable, nonisolated` so they can be called from any actor. Concrete implementations push blocking work onto detached tasks.

| File | Purpose |
|---|---|
| `FileSystemService.swift` | `FileSystemServiceProtocol.listDirectory(at:showHidden:) async throws -> [FileItem]`. The implementation runs inside `Task.detached`, pre-fetches resource keys (name, isDirectory, fileSize, modification/creation dates, hidden, symbolic-link), and resolves symlink targets to mark `isSymlinkToDirectory`. |
| `FileOperationService.swift` | Copy, move, trash (returns trash URLs), permanent delete, create folder, rename. Long-running calls accept `@Sendable` callbacks: `onProgress: (FileOperationProgress) -> Void` and `onConflict: (FileConflict) async -> ConflictResolution { overwrite \| skip \| rename(String) }`. Errors are typed via `FileOperationError`. |
| `ConfigurationService.swift` | `@Observable`, `@MainActor`. Reads bundled `Resources/DefaultConfig.kdl`, merges user overrides from `~/Library/Application Support/com.xvir.LCdrData/config.kdl`, exposes `current: AppConfiguration` plus `lastAppliedUserKDL` for the editor's right pane. Parses with `kdl-swift`. |
| `BookmarkService.swift` | Static helpers around security-scoped bookmark data — `bookmarkData(for:)`, `url(fromBookmarkData:)`. Resolution does **not** auto-start the security scope; callers manage `startAccessingSecurityScopedResource()` themselves. |
| `SandboxAccessService.swift` | `@Observable`. When a permission error surfaces, presents an `NSOpenPanel` pre-navigated to the offending directory so the user can grant access; tracks `grantedURLs` for the session. `isPermissionError(_:)` recognises POSIX `EPERM` and Cocoa file-permission errors (codes 257, 513). |
| `DirectoryWatcher.swift` | `@unchecked Sendable`. Wraps `DispatchSource.makeFileSystemObjectSource` over a file descriptor opened with `O_EVTONLY`. Watches write/delete/rename/attrib/extend/revoke and fires `onChange` on the main queue. |
| `PanelPathStore.swift` | `Sendable` UserDefaults wrapper. Saves/restores `panelPath.{left,right}` plus optional `panelBookmark.{left,right}` so panel directories survive across launches even for sandboxed paths. Bookmark resolution is tried first; raw paths are the fallback. |
| `QuickLookPreviewController.swift` | `@MainActor` adapter for the system Quick Look preview panel. |

### 3.4 ViewModels/ — `@Observable` coordinators (all `@MainActor`)

| File | Purpose |
|---|---|
| `AppState.swift` | App-level state. Owns `leftPanel` and `rightPanel` (`PanelViewModel`s), tracks `activePanel: PanelSide`, owns the shared `FileOperationViewModel` and the `ConfigurationService`. Restores panel directories on init, exposes `switchActivePanel()`, `savePanelPaths()`, `releasePanelSecurityScope()`, `applyEffectiveConfiguration()`, `presentOpenFolderPanel()`, `copySelectedPathsToPasteboard()`, `navigateActivePanelToFavorite(path:)`. |
| `PanelViewModel.swift` | One per panel. Drives directory loading, sorting, selection, focus, history (back/forward), path-bar editing, sandbox-retry flow, and Quick Look. Type-ahead lives here: `typeAheadBuffer` plus `typeAheadResetInterval = 1.0` second of silence resets the buffer (`PanelViewModel.swift:34`). After file operations, `reloadKeepingSelection()` preserves selected IDs and falls back gracefully if the focused item was deleted. |
| `FileOperationViewModel.swift` | The dialog-and-progress coordinator. Drives confirmation alerts, the new-folder alert, the rename sheet, the conflict dialog (with apply-to-all), and the progress overlay. Modal flows are implemented with `CheckedContinuation` so an in-flight async operation can `await` user input without blocking the main actor. Cancellation is via the stored `currentTask: Task<Void, Never>?`. |

### 3.5 Views/ — SwiftUI presentation

| File | Purpose |
|---|---|
| `MainWindowView.swift` | Root view. Builds an `HSplitView` with two `PanelView`s (min 300pt each), stacks `CommandBarView` underneath, and owns the keyboard `KeyShortcutModifier` that maps Tab / Return / Cmd+L / F2–F8 / Delete / Cmd+Delete / Space / type-ahead. Hosts confirmation, conflict, new-folder, rename, and error dialogs. Reloads both panels via `.task` and `NSApplication.didBecomeActiveNotification`. |
| `PanelView.swift` | One panel: `PathBarView` → `FileTableView` (or error message) → `StatusBarView`. Active panel gets a tinted border and accent-coloured background. Tap activates the panel. |
| `FileTableView.swift` | The scrollable list. Multi-select bound to `selectedItemIDs`; `ScrollViewReader` scrolls to `focusedItemID`; intercepts `.onDeleteCommand` (so the OS' default delete behaviour doesn't fire); accepts `.fileURL` drag-drops; pulls font size and date format out of custom `EnvironmentKey`s. |
| `PathBarView.swift` | Breadcrumb path components plus an editable text field (entered via Cmd+L). |
| `CommandBarView.swift` | Bottom strip of six F-key buttons (F3 View, F4 Edit, F5 Copy, F6 Move, F7 Mkdir, F8 Delete); each is disabled when not applicable. |
| `StatusBarView.swift` | Item counts and selected-size summary. |
| `FileOperationProgressView.swift` | Sheet showing operation progress with a Cancel button. |
| `ConflictResolutionView.swift` | Overwrite / Skip / Rename dialog with an apply-to-all toggle. |
| `RenameDialogView.swift` | Inline rename sheet for a single item. |
| `ConfigurationView.swift` | The Settings window. Two-pane `HSplitView`: left is a read-only render of bundled `DefaultConfig.kdl` with KDL syntax highlighting; right is an editable `TextEditor` for user overrides. Apply parses and writes; Cancel reverts to the last applied user KDL. |

### 3.6 Utilities/

| File | Purpose |
|---|---|
| `KeyboardShortcuts.swift` | Centralised shortcut enum. Cmd+Up / Cmd+Down for parent/open, Cmd+L for path bar, Cmd+R refresh, Cmd+\[ / Cmd+] history, Cmd+Shift+. toggles hidden, Cmd+Delete permanent delete. F-keys are constructed from Unicode private-use scalars `0xF705`–`0xF70B` (matching macOS `NSF*FunctionKey` constants), since SwiftUI's `KeyEquivalent` does not expose them directly. |
| `FileFormatter.swift` | `formatSize(_:)` via `ByteCountFormatter`, `formatDate(_:)` with a configurable pattern, `kind(for:)` returning "Parent" / "Alias" / "Folder" / extension / "Document". |
| `KDLSyntaxHighlighter.swift` | Produces an `AttributedString` from KDL text for the configuration editor. |
| `PanelDisplayPreferences.swift` | Defines `EnvironmentKey`s for `lcPanelDateFormat` and `lcPanelFontSize` so the table can pull display preferences from the environment without ViewModels having to plumb them through. |

### 3.7 Resources/

`DefaultConfig.kdl` — the bundled defaults consumed by `ConfigurationService`. Current contents:

```kdl
panel {
    show-hidden-files #false
    sort-by name
    sort-ascending #true
}
appearance {
    font-size 13
    date-format "yyyy-MM-dd HH:mm"
}
bookmarks {
    - "Projects|~/Projects"
    - "Downloads|~/Downloads"
}
editor {
    default-app "com.apple.TextEdit"
}
```

Bookmark entries use a `label|path` string format inside a list-of-children block; `~` is expanded to the user's home directory at parse time.

---

## 4. Concurrency model

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes every type implicitly `@MainActor` unless explicitly opted out — so all ViewModels, UI-touching services, and views are main-thread by default.
- Data models (`FileItem`, `FileOperation*`, `FileSortDescriptor`, `AppConfiguration`, `BookmarkEntry`, `PanelState`) are `Sendable` value types.
- Service **protocols** are `Sendable, nonisolated`; their implementations push blocking I/O into `Task.detached` blocks. This is why `FileSystemService.listDirectory` and every `FileOperationService` method are safe to call from `@MainActor` ViewModels without blocking the UI.
- Long-running operations that need to talk back to the UI use `@Sendable` callbacks for progress and conflict resolution. Conflict resolution further uses `CheckedContinuation` so the async operation can pause until `ConflictResolutionView` resumes it from the main actor.
- `FileItem.init` and `stableID(for:)` are `nonisolated` so the type composes cleanly inside Sendable contexts (e.g. arrays returned from detached tasks).
- `DirectoryWatcher` is `@unchecked Sendable` — `DispatchSource` is thread-safe but not auto-`Sendable`.

---

## 5. Data flow walk-throughs

### Launch
1. `LCdrDataApp` builds `AppState` as `@State` once.
2. `AppState.init` loads `ConfigurationService`, asks `PanelPathStore.restore()` for the last left/right URLs (bookmark resolution first, raw path fallback), and constructs both `PanelViewModel`s sharing one `SandboxAccessService`.
3. `MainWindowView.task` calls `loadDirectory()` on each panel.
4. `FileSystemService.listDirectory` runs on a detached task with pre-fetched resource keys.
5. The panel sorts the result, prepends a synthetic `..` entry via `FileItem.parentEntry`, starts a `DirectoryWatcher` on the new path, and publishes `state.items`.

### F5 Copy
1. The keyboard handler in `MainWindowView` calls `FileOperationViewModel.requestCopy(from:to:)` with the active panel's selection and the inactive panel's directory.
2. The VM builds a confirmation message and shows the alert.
3. On confirm, `executeCopy` invokes `FileOperationService.copy(...)` with `@Sendable` progress and conflict callbacks.
4. The progress callback drives the progress overlay; the conflict callback suspends on a `CheckedContinuation` until the user resolves `ConflictResolutionView`, then resumes with `.overwrite | .skip | .rename`.
5. On completion, both panels run `reloadKeepingSelection()`, which preserves selected IDs (or falls back to a sensible focus position if items disappeared).

### Configuration apply
1. The user edits the right pane in `ConfigurationView` and clicks Apply.
2. `ConfigurationService.apply(fromUserKDL:)` parses the text with `kdl-swift`, merges over the bundled defaults, validates, and writes to `~/Library/Application Support/com.xvir.LCdrData/config.kdl`.
3. `current: AppConfiguration` and `lastAppliedUserKDL` update.
4. `AppState.applyEffectiveConfiguration()` propagates the new sort, hidden-files toggle, font size, and date format to both `PanelViewModel`s.

---

## 6. Persistence surfaces

| Surface | Owner | Keys / paths |
|---|---|---|
| UserDefaults | `PanelPathStore` | `panelPath.left`, `panelPath.right`, `panelBookmark.left`, `panelBookmark.right` |
| Application Support | `ConfigurationService` | `~/Library/Application Support/com.xvir.LCdrData/config.kdl` (user overrides only — defaults stay in the bundle) |
| App-scope bookmarks | `BookmarkService` | Encoded into UserDefaults via `PanelPathStore`; resolved without auto-starting security scope |

---

## 7. Dependencies

| Package | Where used |
|---|---|
| [`kdl-swift`](https://github.com/danini-the-panini/kdl-swift) ≥ 2.0 | `ConfigurationService` only — parses `DefaultConfig.kdl` and user overrides into `KDLDocument` |
| [`swift-mocking`](https://github.com/DanielCardonaRojas/swift-mocking) ≥ 0.1 | Test target only — generates mocks for the `FileSystemService` and `FileOperationService` protocols |

System frameworks in use: SwiftUI, AppKit (`NSOpenPanel`, `NSWorkspace`, `NSPasteboard`, `NSApplication`), Foundation, Observation (`@Observable`), Dispatch (`DispatchSource`), Darwin (`open`/`close` for FD-based watching), CryptoKit (SHA256 for `FileItem.id`), UniformTypeIdentifiers (drag-drop UTType matching).

---

## 8. Tests

Unit tests under `LCdrDataTests/` (Swift Testing):

| File | Coverage |
|---|---|
| `AppStateTests.swift` | App-level state initialisation, active-panel switching |
| `ConfigurationServiceTests.swift` | KDL parsing, defaults, user-override merging, file I/O |
| `FileFormatterTests.swift` | Size / date / kind formatting |
| `FileItemTests.swift` | Stable SHA256-derived IDs, parent-entry construction |
| `FileOperationServiceTests.swift` | Copy / move / trash / permanent-delete / mkdir / rename, conflict callbacks, progress reporting |
| `FileOperationTests.swift` | Operation kind / status / progress models |
| `FileOperationViewModelTests.swift` | Dialog flows, confirmation, conflict resolution, cancellation |
| `FileSortDescriptorTests.swift` | Column toggle and direction logic |
| `FileSystemServiceTests.swift` | Listing behaviour against mock FS |
| `PanelStateTests.swift` | State initialisation invariants |
| `PanelViewModelTests.swift` | Loading, selection, navigation, history |
| `PanelViewModelPhase3Tests.swift` | Keyboard shortcut and type-ahead behaviour |

Mocks for service protocols are produced via `swift-mocking`. Tests are written `@MainActor` because the ViewModels they exercise are main-actor-isolated.

UI tests under `LCdrDataUITests/` (XCTest): `LCdrDataUITests.swift` covers basic launch and interaction; `LCdrDataUITestsLaunchTests.swift` records launch performance metrics. Per `CLAUDE.md`, UI tests are not part of the routine development loop — run them manually only.

---

## 9. Divergence from DESIGN.md

These items in `DESIGN.md` are not (yet) reflected in code:

- **No standalone `SearchService`.** Type-ahead incremental match lives inside `PanelViewModel` (with a 1-second silence reset). There is no separate search facility.
- **No tabs per panel.** Each side hosts a single panel.
- **`DefaultConfig.kdl` shape.** DESIGN.md sketches `bookmark "Label" "Path"` per-bookmark nodes; the actual file uses a `bookmarks { - "label|path" ... }` list shape, which is what `ConfigurationService.appConfiguration(from:mergingOnto:)` parses today.

When implementing any of the above, expect to update both files.

---

## 10. Conventions worth preserving

Observations about how the code is organised today, useful for keeping new work consistent:

- **Protocol-fronted services.** Anything I/O-heavy hides behind a `Sendable, nonisolated` protocol so it can be mocked and swapped in tests.
- **Deterministic identity for list rows.** `FileItem.id` is derived from URL via SHA256 to keep SwiftUI list identity stable across reloads — important for selection preservation and for avoiding row flicker on `reloadKeepingSelection`.
- **Async continuations for modal dialogs.** `FileOperationViewModel` uses `CheckedContinuation` to pause an in-flight operation while the user resolves a conflict or confirmation, instead of restructuring the operation as a state machine.
- **`@Sendable` callbacks for boundary crossings.** Progress and conflict callbacks are explicitly `@Sendable` so they're safe to call from detached tasks.
- **Centralised keyboard shortcuts.** Shortcut definitions live in one `KeyboardShortcuts` enum rather than being scattered across views — including the `0xF705`-and-up scalar trick for F-keys.
- **Custom `EnvironmentKey`s for display prefs.** `PanelDisplayPreferences` lets the file table pull font size / date format from the environment without ViewModels having to forward them.
- **No file headers.** Per `CLAUDE.md`, Swift files start directly with `import` lines.
