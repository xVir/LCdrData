# CURRENT_ARCH.md — LCdrData

A snapshot of the **as-built** architecture, distinct from the intended design.

> **`DESIGN.md`** is the spec — what LCdrData is meant to become.
> **`CURRENT_ARCH.md`** (this file) is the reality — what the code on `develop` actually does today.
>
> When the two disagree, the code wins; see [§10 Divergence from DESIGN.md](#10-divergence-from-designmd).
>
> _Last updated: 2026-08-21 (branch `develop`), after the layered modularisation._

LCdrData is a native macOS dual-panel file manager built with SwiftUI on Swift 6 strict concurrency. All types default to `@MainActor`. The app is sandboxed with user-selected read-write file access and app-scope security-scoped bookmarks. Configuration is a KDL document. Multiple windows are supported, each with its own panel pair over one shared set of services.

---

## 1. Top-level layout

```
LCdrData/
├── MODULE.bazel               Bazel dependencies (bzlmod)
├── BUILD.bazel                Shared config only; targets are per-package
├── defs.bzl                   Shared SWIFT_COPTS and PACKAGE_NAME
├── .bazelversion              9.2.0 (pinned)
├── Bazel/                     Hand-written Info.plist and entitlements
├── Project.swift              Tuist target manifest (mirrors the module split)
├── Tuist/Package.swift        SPM declarations — read by Tuist AND Bazel
├── .tuist-version             4.182.0 (pinned)
├── LCdrData/                  BUILD.bazel here defines //LCdrData (the app)
│   ├── Core/                  Layer 1 — Utilities, Models, Bindings, Formatting
│   ├── Services/              Layer 2 — file I/O, sandbox, config, watching
│   ├── ViewModels/            Layer 3 — @Observable state coordinators
│   ├── App/                   Layer 4 (AppEnvironment) + layer 6 (entry point)
│   ├── Views/                 Layer 5 — SwiftUI presentation
│   └── Resources/             DefaultConfig.kdl
├── LCdrDataTests/             Swift Testing unit tests, one target per module
└── LCdrDataUITests/           XCTest UI tests
```

Bazel is the build system; Tuist generates the Xcode project. The `.xcodeproj` and `.xcworkspace` are not committed — run `tuist install && tuist generate` when you need the IDE. See `AGENTS.md` for which tool does which job and `BAZEL_MIGRATION.md` for why the split exists.

---

## 2. Build & target settings

| Setting | Value |
|---|---|
| Bazel | 9.2.0 (builds the app, runs unit tests) |
| Tuist | 4.182.0 (Xcode project, UI tests) |
| Swift | 5.0 (compiler), with Swift 6 concurrency features enabled |
| Deployment target | macOS 26.4 |
| Destinations | `.mac` only |
| Bundle ID (app) | `com.xvir.LCdrData` |
| App Sandbox | enabled |
| User-selected files | `readwrite` |
| Bookmarks | app-scope |
| Default actor isolation | `MainActor` |
| Approachable concurrency | `YES` |
| Member import visibility | `YES` |
| Swift package name | `lcdrdata` — must match `PACKAGE_NAME` in `defs.bzl` for `package` declarations to resolve |

Debug builds carry extra entitlements (`get-task-allow` plus two `testmanagerd` exceptions) because an app-hosted `macos_unit_test` cannot otherwise bootstrap. `--config=release` selects the two production keys.

---

## 3. Module layering

The app is nine Swift modules. Layer 1 is two independent leaves plus two small
modules that combine them; from layer 2 up it is a straight stack.

```
                       ┌─ Formatting ─┐
App → Views → AppEnvironment → ViewModels → Services ─→ Models
                       └─ Bindings ───┴──────────────→ Utilities
```

| Layer | Module | Bazel target | Depends on |
|---|---|---|---|
| 1 | `Utilities` | `//LCdrData/Core/Utilities` | nothing |
| 1 | `Models` | `//LCdrData/Core/Models` | nothing |
| 1½ | `Formatting` | `//LCdrData/Core/Formatting` | `Models` |
| 1½ | `Bindings` | `//LCdrData/Core/Bindings` | `Models`, `Utilities` |
| 2 | `Services` | `//LCdrData/Services` | `Models` |
| 3 | `ViewModels` | `//LCdrData/ViewModels` | layer 1 and 2 |
| 4 | `AppEnvironment` | `//LCdrData/App:AppEnvironment` | `Models`, `Services`, `ViewModels` |
| 5 | `Views` | `//LCdrData/Views` | everything below |
| 6 | `App` | `//LCdrData/App:LCdrDataLib` | everything below |

Four facts about this shape are load-bearing:

- **`Core/` is four directories, one per module**, and `Bindings/` and `Formatting/` hold a single file each. That looks fussy until you see what it buys: `CommandCatalog` needs both a `Command` and a `KeyboardShortcuts` key, and `FileFormatter.kind(for:)` takes a `FileItem`, so housing either with `Models` or `Utilities` would make those two mutually dependent — which is exactly what forced them to be one module before. Given their own modules, both leaves are free of first-party dependencies.
- **Module names avoid the types they contain.** `Formatting` rather than `FileFormatter`, `Bindings` rather than `CommandCatalog`, because a module and a type sharing a name makes every reference from a client ambiguous.
- **`AppEnvironment` is its own layer**, sharing the `App/` directory with layer 6 but built as a separate target. `Views` needs it while it needs `ViewModels`, which is what breaks the App ↔ Views cycle.
- **Each module's BUILD file names, via `visibility`, exactly which packages may depend on it**, so a layering violation is an analysis-time error rather than a review comment. It bites in both directions: `Models` cannot reach up to `Services`, and a test target for one layer cannot reach past it either.

Types that cross a module boundary are declared `package`, not `public` — roughly forty of them. The widening stops at the package rather than becoming API. Every target shares `package_name = "lcdrdata"`, which is why splitting `Core` into four required no access-level changes at all.

One consequence of `MemberImportVisibility` is worth knowing: a file can need `import Models` without naming a single `Models` type, because reaching a *member* of a type — `panel.state.sortDescriptor` — requires the defining module to be imported. Several imports exist for that reason alone and look redundant.

---

## 4. Layers, file by file

### 4.1 Core/Models — value types

| File | Purpose |
|---|---|
| `BrowseLocation.swift` | The real place a panel is browsing: `.directory(URL)` or `.zipArchive(container:internalPath:)`. Supplies archive-aware parent navigation, display path, watcher URL, and the real containing directory used for persistence. |
| `FileItem.swift` | `nonisolated struct FileItem: Identifiable, Hashable, Sendable`. Filesystem and archive rows share one model; archive identity stores the real container plus internal path and hashes `"zip:<container>!<path>"`. `isEnterable` includes filesystem directories and top-level `.zip` files without treating zip members as nested archives. |
| `PanelState.swift` | Per-panel snapshot: `location`, `items`, `cursor`, `sortDescriptor`, `showHiddenFiles`, location history and index. Compatibility accessors expose the persistent filesystem directory where older call sites require one. |
| `Cursor.swift` | `struct Cursor: Sendable, Equatable` — the panel's attention model. `focused: UUID?` is the single row driving Quick Look, the sort anchor and type-ahead; `selected: Set<UUID>` is what the next file operation acts on. Owns both the user-event mutations (`userDidSelect`, `selectAll`, `focusFirst`…) and `resolve(intent:listing:previousListing:previousCursor:)`, which decides where the cursor lands after a reload. |
| | `Cursor.Intent` makes that decision explicit at the call site: `.fresh`, `.keepSelection`, `.landOnChild(URL)` after going to a parent, `.landOnNeighbourOf([URL])` after a delete or move, `.landOnNew(URL)` after a rename or mkdir. |
| `Command.swift` | `enum Command: Equatable` — the closed set of user actions, 22 cases across navigation, open/view, selection, file operations and clipboard. Mostly parameterless; `.openItem(FileItem)` and `.rename(FileItem)` carry explicit targets. |
| `CommandCatalog.swift` | Maps `Command` to its keyboard binding and nothing else — `binding(for:)`, `shortcut(for:)`, `keyEquivalent(for:)`. Deliberately excludes titles, which each surface labels itself. |
| `FileContextMenuModel.swift` | The pure decision layer behind context menus: given a selection and a listing, resolves the `.selection` / `.parent` / `.background` variant and the real (non-`..`) items to act on. |
| `FileOperation.swift` | `FileOperationKind` (copy / move / delete / permanentDelete / createFolder / rename), `FileOperationStatus`, `FileOperationProgress` with computed `fractionCompleted`, and the operation struct with its `displayDescription`. |
| `PanelSession.swift` | Window identity and collapsed left/right paths for `WindowGroup(for:)`. Optional live `BrowseLocation`s let `⌘N` clone archive interiors; custom Codable deliberately omits them so relaunch restores only real containing directories. |
| `SortDescriptor.swift` | `FileSortDescriptor` with `Column { name, size, dateModified, dateCreated, kind }`; `toggle(column:)` flips direction on the same column and resets to ascending on a new one. |
| `AppConfiguration.swift` | Effective settings with defaults (hidden off, sort by name ascending, font 13, date `yyyy-MM-dd HH:mm`, editor `com.apple.TextEdit`); nested `BookmarkEntry { label, path }`; computed `sortDescriptor`. |

### 4.2 Core/Utilities

| File | Purpose |
|---|---|
| `KeyboardShortcuts.swift` | The F2–F8 `KeyEquivalent` values SwiftUI does not expose, built from Unicode private-use scalars `0xF705`–`0xF70B` to match the `NSF*FunctionKey` constants. Consumed by `CommandCatalog`. |
| `TildePathExpander.swift` | Expands `~` and `~/…` against the **real account home** via `getpwuid`, not the sandbox container home, which is what `NSHomeDirectory()` would give. Fronted by `HomeDirectoryProviding` so tests can stub the account database. Only exact `~` and `~/…` expand; `~user` passes through. |
| `FileFormatter.swift` | `formatSize` via `ByteCountFormatter`, `formatDate` with a configurable pattern, and `kind(for:)` returning "Parent" / "Alias" / "Folder" / extension / "Document". |
| `KDLSyntaxHighlighter.swift` | Builds an `AttributedString` from KDL source for the configuration editor. |
| `PanelDisplayPreferences.swift` | `EnvironmentKey`s for `lcPanelDateFormat` and `lcPanelFontSize`, so the table pulls display preferences from the environment instead of ViewModels plumbing them through. |
| `Notifications.swift` | `Notification.Name.lcdrConfigurationApplied`. It lives in Core so `Views` can observe it without depending on `App`. |

### 4.3 Services — protocol-fronted I/O

Service protocols are `Sendable, nonisolated` so they can be called from any actor; the implementations push blocking work onto detached tasks.

| File | Purpose |
|---|---|
| `FileSystemService.swift` | `FileSystemServiceProtocol.listDirectory(at:showHidden:) async throws -> [FileItem]`. Runs in `Task.detached`, pre-fetches resource keys, and resolves symlink targets to mark `isSymlinkToDirectory`. |
| `FileOperationService.swift` | Copy, move, trash (returns trash URLs), permanent delete, create folder, rename. Long-running calls take `@Sendable` callbacks — `onProgress: (FileOperationProgress) -> Void` and `onConflict: (FileConflict) async -> ConflictResolution`. Per-item cancellation via `Task.checkCancellation()`; a source and destination resolving to the same path is a no-op rather than an error. Typed failures via `FileOperationError`. |
| `FileOpeningService.swift` | `FileOpeningServiceProtocol.open(_:preferredApplicationBundleID:)`, the `F4` target. Resolves the configured bundle ID through `WorkspaceApplicationOpening` and falls back to the system default handler when it is absent or not installed. See §4a. |
| `ArchiveService.swift` | `ArchiveServiceProtocol` and its ZIPFoundation-backed actor. Lists explicit and implicit folders, extracts with zip-slip checks, packs files and trees, removes prefixes, creates folders, renames, and rejects mutations when the container is not writable. |
| `BrowseOperationService.swift` | Routes copy, move, delete, mkdir, and rename across the filesystem/zip location matrix. Cross-archive transfers use scoped temporary extraction, preserve conflict choices, and only remove source members that were actually transferred. |
| `ConfigurationService.swift` | `@Observable`, `@MainActor`. Reads bundled `DefaultConfig.kdl`, merges user overrides, exposes `current: AppConfiguration` and `lastAppliedUserKDL` for the editor's right pane. Parses with `kdl-swift`. |
| `BookmarkStore.swift` | The bookmark database: `BookmarkStore` persists security-scoped bookmark blobs in `UserDefaults` keyed by path, resolves them, refreshes stale ones, and answers `bookmarkCovering(url:)` by longest matching prefix. `@unchecked Sendable`, `NSLock`-guarded. Fronted by `BookmarkStoreProtocol`, with bookmark encoding itself behind `BookmarkSerializing` so tests never touch the real macOS API. |
| `BookmarkService.swift` | `nonisolated static` helpers wrapping `.withSecurityScope` bookmark creation and resolution, returning refreshed data when stale. Resolution deliberately does **not** start the security scope. |
| `SandboxAccessService.swift` | `package actor`. Coordinates access requests, coalescing concurrent ones single-flight by `AccessRequestContext.dedupKey`, and saves a bookmark on grant. `isPermissionError(_:)` is `nonisolated static` and recognises POSIX `EPERM` plus Cocoa file-permission codes 257 and 513. |
| `AccessPresenter.swift` | `AccessPresenter` protocol — `present(_ context:) async -> URL?`. `NSOpenPanelAccessPresenter` (`@MainActor`) drives a context-titled `NSOpenPanel` pre-navigated to the offending directory; `NoopAccessPresenter` always declines. |
| `AccessRequestContext.swift` | Why access is being asked for: `.startup`, `.reactive(displayURL:resolvedTarget:)`, `.manualGrant(suggestedURL:)`. Supplies the dedup key. |
| `DirectorySession.swift` | Watches a directory or the current zip container over an `O_EVTONLY` file descriptor with `DispatchSource.makeFileSystemObjectSource` (write/delete/rename/attrib/extend/revoke), debouncing to `onChange` after **0.28 s**. Short-lived and replaced on navigation. |
| `PanelSessionStore.swift` | `PanelSessionStoring` over `UserDefaults`: the last left/right directory paths, so a relaunch resumes even when macOS window restoration does not run. |
| `QuickLookPreviewController.swift` | `@MainActor` `QLPreviewPanelDataSource` adapter for the system Quick Look panel. |

### 4.4 ViewModels — `@Observable` coordinators

| File | Purpose |
|---|---|
| `PanelViewModel.swift` | One per panel. Dispatches listing by `BrowseLocation`, enters and leaves zip locations atomically, watches the directory or container, tracks archive writability, and temporarily extracts members for Quick Look/F4/drag-out. |
| `AppState.swift` | **Per-window** state: `leftPanel`, `rightPanel`, `activePanel`, the window's `FileOperationViewModel`, its `QuickLookPreviewController`, and a reference to the shared `ConfigurationService`. Exposes `switchActivePanel()`, `applyEffectiveConfiguration()`, `presentOpenFolderPanel()`, `copySelectedPathsToPasteboard()`, `navigateActivePanelToFavorite(path:)`, and a computed `commands: CommandRunner`. |
| `CommandRunner.swift` | `package struct`. The single executor for `Command`, resolving active and inactive panels from one `AppState` and answering `isEnabled(_:)` so every surface greys out consistently. |
| `FileOperationViewModel.swift` | The dialog-and-progress coordinator over `BrowseOperationService`: location-aware confirmations, external drops, mkdir/rename/delete, and cross-filesystem/archive copy and move. Conflict resolution still suspends on a `CheckedContinuation`. |
| `FocusedAppState.swift` | Declares `ActiveAppStateKey` and `FocusedValues.appState` so menu commands act on the key window's `AppState` rather than a captured one. (There is no type named `FocusedAppState`.) |

### 4.5 App/AppEnvironment — shared services

`AppEnvironment` is the one thing every window shares: `ConfigurationService`, `BookmarkStore`, `SandboxAccessService`, `PanelSessionStore`, the security-scope activator, and a weak `mostRecentAppState`.

| Method | Purpose |
|---|---|
| `start()` | Idempotent. Starts the security scope on every stored bookmark, then — if no bookmark covers the account home — requests startup access to it. |
| `makeFreshSession()` | Seeds a new window, preferring the frontmost window's paths, then the last saved session, then home for both panels. |
| `rememberLastSession(_:)` | Writes the current paths through `PanelSessionStore`. |
| `releaseAllScopes()` | Stops every active scope; called from `applicationWillTerminate`. |

Scope activation is fronted by `SecurityScopeActivating` so tests can observe start/stop calls without touching real bookmarks.

### 4.6 Views — SwiftUI presentation

| File | Purpose |
|---|---|
| `WindowRootView.swift` | The per-window shell, and not where the UI lives. It builds the window's `AppState` from its `PanelSession`, publishes it as a focused scene value, awaits `env.start()`, saves a bookmark and updates the session binding on every directory change, and applies configuration when `lcdrConfigurationApplied` arrives. |
| `MainWindowView.swift` | The dual-panel layout: `HSplitView` of two `PanelView`s (min 300 pt each) over `CommandBarView`. Hosts the confirmation, conflict, new-folder, rename and error dialogs plus the progress overlay, and contains the private `KeyShortcutModifier` that routes window-level keys. |
| `PanelView.swift` | One panel: `PathBarView` → `FileTableView` (or an error state) → `StatusBarView`, with the active panel tinted and bordered. Tapping activates it. |
| `FileTableView.swift` | The list itself, with sortable column headers, selection bound to the cursor, scroll-to-focused, context menus, drag out and `.fileURL` drop in. Intercepts `.onDeleteCommand` to navigate to the parent, because the table consumes Delete before window-level routing sees it. |
| `PathBarView.swift` | Breadcrumb components, the Cmd+L editable field, and a copy-path button. |
| `CommandBarView.swift` | The bottom F3–F8 strip; each button asks `CommandRunner.isEnabled` and calls `perform`. |
| `StatusBarView.swift` | Item counts and selected-size summary. |
| `FileContextMenu.swift` | The secondary-click menu, in three variants resolved by `FileContextMenuModel`, routed through `CommandRunner`. |
| `FileOperationProgressView.swift` | The copy/move progress overlay with Cancel. Not shown for trash or delete. |
| `ConflictResolutionView.swift` | Overwrite / Skip / Rename with an apply-to-all toggle; resumes the continuation in `FileOperationViewModel`. |
| `RenameDialogView.swift` | The rename sheet for a single item. |
| `ConfigurationView.swift` | The Settings window: a two-pane `HSplitView` with syntax-highlighted bundled defaults on the left and an editable overrides pane on the right. Apply parses, merges, writes and closes — it leaves the window open only when the KDL is rejected, so the inline error stays readable; Cancel reverts the pane to the last applied text and closes. Both close via `@Environment(\.dismiss)` — the revert matters because the `Settings` scene keeps the view alive across closes. |

### 4.7 App — entry point

| File | Purpose |
|---|---|
| `LCdrDataApp.swift` | `@main`. Holds the single `@State AppEnvironment`, declares `WindowGroup(for: PanelSession.self)` with `env.makeFreshSession()` as its default value, attaches `MainCommands`, and declares the `Settings` scene hosting `ConfigurationView`. |
| `MainCommands.swift` | The menu bar — Open Folder, Grant Folder Access, the config-driven Favorites menu, and navigation, selection and delete commands, all acting on `@FocusedValue(\.appState)` with shortcuts from `CommandCatalog`. |
| `AppDelegate.swift` | Quits when the last window closes; releases all security scopes on terminate. |

### 4.8 Resources

`DefaultConfig.kdl` — the bundled defaults, at `Contents/Resources/DefaultConfig.kdl`, which is where `ConfigurationService` looks:

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
    open-folders #false
}
```

Bookmark entries use a `label|path` string inside a dash-list block, and `~` is expanded at parse time.

### 4a. How `editor.default-app` reaches F4

`AppConfiguration.editorDefaultAppBundleID` and `editorOpenFolders` travel the same path as
`sortDescriptor` and `panelShowHiddenFiles`: `AppState` pushes them into both panels, at init
and again from `applyEffectiveConfiguration()` when the settings window applies. No panel
reads `ConfigurationService` itself.

`PanelViewModel` then hands it to `FileOpeningService` (layer 2), whose one job is
resolve-or-fall-back:

| Configured bundle ID | Installed? | Result |
|---|---|---|
| set | yes | `NSWorkspace.open(_:withApplicationAt:configuration:)` with that app |
| set | no | system default handler |
| absent | — | system default handler |

The fallback is deliberate and silent, so `F4` always opens something even with a typo in the
KDL. `WorkspaceApplicationOpening` brackets the three `NSWorkspace` calls involved so the
decision is unit-testable without launching an application.

What `F4` is willing to act on is decided by `PanelViewModel.editTargetItem()`, kept separate
from `preparedSelectedFileURL()` on purpose — Quick Look (`F3`) shares that one and stays
files-only:

| Selection | `open-folders` off | on |
|---|---|---|
| a file | opened (archive members extracted first) | same |
| a folder, incl. `..` | nothing | opened |
| a folder inside a ZIP | nothing | nothing |

Archive folders are excluded in both states: the editor would receive an extracted copy whose
edits never reach the container, which reads as data loss. `CommandRunner.isEnabled` therefore
asks `hasEditTarget` for `.edit` rather than sharing `.quickLook`'s check, so the command bar's
Edit button tracks the setting instead of staying greyed out over a folder.

**This is the `Edit` (`F4`) path only.** `openItem` — Enter and double-click — still calls
`NSWorkspace.shared.open` directly and keeps the system default handler, so pressing Enter on
a `.png` opens Preview while `F4` opens the configured editor.

---

## 5. Concurrency model

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes every type implicitly `@MainActor` unless it opts out, so ViewModels, views and UI-touching services are main-thread by default.
- Data models (`FileItem`, `Cursor`, `FileOperation*`, `FileSortDescriptor`, `AppConfiguration`, `PanelSession`) are `Sendable` value types. `PanelState` is not — it holds main-actor state.
- Service **protocols** are `Sendable, nonisolated`; implementations push blocking I/O into `Task.detached`. That is why `listDirectory` and the `FileOperationService` methods are safe to call from `@MainActor` without blocking the UI.
- `SandboxAccessService` is a genuine `actor`, which is what makes its single-flight dedup correct under concurrent requests from several windows.
- `BookmarkStore` and `DirectorySession` are `@unchecked Sendable` with explicit synchronisation — an `NSLock` and a private serial `DispatchQueue` respectively — because `UserDefaults` and `DispatchSource` are thread-safe but not automatically `Sendable`.
- Long-running operations talk back through `@Sendable` callbacks, and conflict resolution uses a `CheckedContinuation` so the async operation can pause until the sheet resumes it.
- `FileItem.init` and `stableID(for:)` are `nonisolated` so the type composes inside Sendable contexts, such as arrays returned from detached tasks.

---

## 6. Data flow walk-throughs

### Launch, and opening a window

1. `LCdrDataApp` creates one `AppEnvironment` as `@State`.
2. `WindowGroup(for: PanelSession.self)` restores a session, or asks `makeFreshSession()` for one — frontmost window's paths, else the last saved session, else home.
3. `WindowRootView` resolves each path through `bookmarkStore.resolve(path:)` (falling back to a plain file URL), builds this window's `AppState`, publishes it as a focused scene value, and awaits `env.start()`.
4. `start()` activates the security scope on every stored bookmark and, if none covers the account home, requests startup access to it.
5. `MainWindowView.task` reloads both panels; each listing runs in a detached task, is sorted, gets a synthetic `..` row prepended, and starts a `DirectorySession` on the new directory.

`⌘N` repeats steps 2–5. Nothing is shared between windows except `AppEnvironment`.

### Reactive sandbox grant

1. `PanelViewModel.navigate(to:)` → `performAtomicNavigation`, which snapshots the panel first.
2. `reload(.fresh)` calls `listDirectory`, which throws; `SandboxAccessService.isPermissionError` recognises it.
3. `performAtomicNavigation` awaits `requestAccessIfNeeded(context: .reactive(...))`, which presents an `NSOpenPanel` at the resolved target and, on grant, saves a bookmark.
4. Granted, it reloads. Refused, it restores the snapshot and reloads with `.keepSelection`, so a denied navigation leaves no visible trace.

`WindowRootView` separately saves a bookmark on every successful directory change, which is how granted folders accumulate. "Grant Folder Access…" in the menu bar goes straight to `requestAccessIfNeeded(context: .manualGrant(...))`.

### A command, from keystroke to effect

Four surfaces raise commands, and all four go through one executor:

| Surface | How it reaches `CommandRunner` |
|---|---|
| Window keys | `KeyShortcutModifier.onKeyPress` → `perform` |
| Command bar | button → `appState.commands.perform` |
| Menu bar | `@FocusedValue(\.appState)` → `focused?.commands.perform` |
| Context menu | button → `appState.commands.perform` |

The split between the window and the menu bar is deliberate. Keys that must work regardless of menu routing — Tab, Return, Home/End, Space, F2–F8, plain Delete, `⌘⌫`, and type-ahead — are handled in `KeyShortcutModifier`. Everything with a natural menu home — parent, refresh, hidden toggle, history, select all, trash — is declared in `MainCommands` with its shortcut from `CommandCatalog`. `F5`, `F6` and `F7` have no menu item at all.

### F5 Copy

1. `KeyShortcutModifier` → `runner.perform(.copy)` → `fileOperations.requestCopy(from: active, to: inactive)`.
2. The view model collects the selected non-parent items and raises the confirmation dialog.
3. On confirm, `confirmOperation` spawns a task into `executeCopy`, which registers a `FileOperation`, shows the overlay, and calls `FileOperationService.copy`.
4. Progress callbacks drive the overlay. A conflict callback suspends on a `CheckedContinuation` until `ConflictResolutionView` resumes it with `.overwrite`, `.skip` or `.rename` — optionally applied to the rest of the batch.
5. On completion both panels reload with an explicit intent, so the cursor lands predictably rather than resetting.

### Configuration apply

1. Apply in `ConfigurationView` calls `ConfigurationService.apply(fromUserKDL:)`, which parses with `kdl-swift`, merges over the bundled defaults, and writes the user file atomically (or deletes it, if the text is empty).
2. It posts `.lcdrConfigurationApplied`.
3. **Every** open `WindowRootView` observes that and calls `appState.applyEffectiveConfiguration()`, which pushes the new sort and hidden-files setting into both panels and reloads them with `.keepSelection`. Font size and date format reach the table through the environment.

The Settings scene never holds an `AppState`; the notification fan-out is what makes one edit apply to every window.

---

## 7. Persistence surfaces

| Surface | Owner | Keys / paths |
|---|---|---|
| `UserDefaults` | `BookmarkStore` | `bookmarks` — `[String: Data]`, URL path → security-scoped bookmark blob |
| `UserDefaults` | `PanelSessionStore` | `lastPanelSession` — `["left": path, "right": path]` |
| Container Application Support | `ConfigurationService` | `~/Library/Containers/com.xvir.LCdrData/Data/Library/Application Support/com.xvir.LCdrData/config.kdl` — user overrides only; defaults stay in the bundle |
| Window restoration | macOS | `PanelSession` values, `Codable`, restored by `WindowGroup(for:)` |

The config path resolves inside the sandbox container because `ConfigurationService` asks `FileManager` for `.applicationSupportDirectory`. `~/Library/Application Support/com.xvir.LCdrData` does not exist.

---

## 8. Dependencies

| Package | Where used |
|---|---|
| [`kdl-swift`](https://github.com/danini-the-panini/kdl-swift) ≥ 2.0 | `ConfigurationService` only — parses `DefaultConfig.kdl` and user overrides |
| [`ZIPFoundation`](https://github.com/weichsel/ZIPFoundation) ≥ 0.9.20 | `ArchiveService` only — reads and rewrites zip containers |

Both direct dependencies are declared in `Tuist/Package.swift`, which Tuist and Bazel read.
Their Bazel targets are dependencies of `Services` alone.

No mocking framework: `swift-mocking` was removed during the Bazel migration, as it was declared but never imported and pulled `swift-syntax` in as a macro dependency. Test doubles are written by hand.

System frameworks: SwiftUI, AppKit (`NSOpenPanel`, `NSWorkspace`, `NSPasteboard`, `NSApplication`), Foundation, Observation, Dispatch, Darwin (`open`/`close`, `getpwuid`), CryptoKit (SHA256 for `FileItem.id`), QuickLookUI, UniformTypeIdentifiers.

---

## 9. Tests

**Eight unit test targets.** The test tree mirrors the production module layout one directory at a time, so every module's tests are a package of their own.

| Target | Files | Covers |
|---|---|---|
| `//LCdrDataTests/Core/Utilities` | 1 | `~` expansion against a stubbed account home |
| `//LCdrDataTests/Core/Models` | 7 | Browse locations, archive/file identity, cursor resolution, panel history, sorting, operation models, context menus |
| `//LCdrDataTests/Core/Bindings` | 1 | Every `Command`'s key and modifiers, and which commands have none |
| `//LCdrDataTests/Core/Formatting` | 1 | Size, date and filesystem/archive kind formatting |
| `//LCdrDataTests/Services` | 9 | Filesystem and ZIP listing/operations, conflicts, extraction safety, watching, configuration, bookmarks, sessions, sandbox access |
| `//LCdrDataTests/ViewModels` | 5 | Panel/archive navigation, selection, history, type-ahead, command guards, Return activation, dialog flows and cancellation |
| `//LCdrDataTests/AppEnvironment` | 1 | Startup scope activation, session seeding, archive-location collapse |
| `//LCdrDataTests/App` | 1 | `AppDelegate` termination behaviour |

`Views` has no unit test target: the views are covered by the UI tests instead.

`//LCdrDataTests/TestSupport` holds the fakes shared across targets — `FakeBookmarkStore`, `FakeAccessPresenter`, `RecordingScopeActivator` and friends. All test doubles are hand-written against the service protocols; there is no mocking framework.

Every target is app-hosted (`test_host = "//LCdrData"`) and tagged `local`, since these do not bootstrap inside Bazel's sandbox, and declares `size = "small"`.

One test is **skipped, not run**: `FileOperationServiceTests.trashFile()` is `@Test(.disabled(...))` because `FileManager.trashItem` needs an application context. It still counts toward the suite total.

UI tests under `LCdrDataUITests/` (XCTest) cover launch, panel selection and session restore. Bazel compiles them but cannot run them — `rules_apple`'s runner rejects macOS XCUITEST — so `scripts/run-ui-tests.sh` delegates to Tuist. They are not part of the routine development loop.

---

## 10. Divergence from DESIGN.md

`DESIGN.md` describes the product as intended and lists what it does not yet cover — tabs,
remappable shortcuts, a toolbar, a volumes list, an inline preview pane, search beyond
type-ahead, and archive browsing. None of those exist in code, and the spec no longer claims
they do, so they are not divergences.

No divergences remain.

`editor.default-app` used to be one: it was parsed into `AppConfiguration` and then never
read, so `F4` fell through to `NSWorkspace.shared.open` and the system default handler.
It is now wired up — see §4a. When implementing anything from the spec's "not in scope yet"
list, expect to update both files.

---

## 11. Conventions worth preserving

- **Layering is enforced, not documented.** Adding a dependency means editing the provider's `visibility`, which makes the widening visible in review. Prefer moving code to widening a list — a test that wants a dependency its layer should not have is usually filed in the wrong place.
- **`package`, not `public`.** Cross-module types widen exactly as far as the package and no further.
- **Protocol-fronted services.** Anything I/O-heavy hides behind a `Sendable, nonisolated` protocol so it can be faked in tests, and the fakes are written by hand.
- **Explicit cursor intents.** `reload(_:)` takes a `Cursor.Intent` so each caller states where the cursor should land. This replaced inferring it from what changed, which was the source of several selection bugs.
- **Deterministic identity for list rows.** `FileItem.id` is SHA256-derived from the URL, keeping SwiftUI list identity stable across reloads.
- **One executor for commands.** Every surface funnels through `CommandRunner`, and enablement is asked rather than duplicated.
- **Async continuations for modal dialogs.** `FileOperationViewModel` pauses an in-flight operation on a `CheckedContinuation` instead of restructuring it as a state machine.
- **`@Sendable` callbacks for boundary crossings.** Progress and conflict callbacks are explicitly `@Sendable` so detached tasks can call them.
- **Centralised keyboard shortcuts.** Bindings live in `CommandCatalog` alone, including the `0xF705`-and-up scalar trick for F-keys.
- **Custom `EnvironmentKey`s for display preferences.** The table pulls font size and date format from the environment rather than having ViewModels forward them.
- **No file headers.** Per `AGENTS.md`, Swift files start directly with `import` lines.

---

## 12. Known framework issues

### The `NSTableView` reentrancy warning

Navigating into a directory with a few hundred entries logs:

```
WARNING: Application performed a reentrant operation in its NSTableView delegate.
This warning will become an assert in the future.
```

It is cosmetic — nothing in the app misbehaves — and it comes from SwiftUI's `List`, not
from our code. **This has been investigated to exhaustion; please do not start over.**

Instrumented runs against a 283-row listing ruled out every application-side suspect. The
warning does not fire from the selection binding, the row tap gestures, Return routing, or
`scrollTo`: it lands 25–42 ms *after* the `state.items` and `state.cursor` assignments have
both returned, on no stack of ours. It correlates with one thing only — the number of rows
being inserted:

| Reload | Rows | Warning |
|---|---|---|
| Fresh listing | 0 → 283 | yes |
| Refresh in place | 283 → 283 | no |
| Navigating back up | 5–13 → 283 | yes, 5 of 5 |

Only reloads that *grow* the list to 283 rows warn. Replacing `state.items` wholesale versus
mutating it in place (`removeAll(keepingCapacity:)` then `append(contentsOf:)`) makes no
difference — both were measured, both warn. That matches the widely reported `List` bug that
appears somewhere above ~200 rows and reproduces in Apple's own sample code.

What remains is an `NSTableView` bridge for the file table, replacing `List`. That is a real
piece of work and is not justified by a cosmetic warning, so it has not been done.
