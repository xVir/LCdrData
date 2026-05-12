# Fix cross-window panel sync (per-window state, SwiftUI-native multi-window)

## Context

LCdrData currently shares one `AppState` across every window. `LCdrDataApp.swift:7` declares `@State private var appState = AppState()` on the `App` struct — `@State` there is **application-scoped**, not window-scoped, so `WindowGroup` hands the same `AppState` (and its `@Observable final class` panels) to every window. Navigating in one window mutates the same `PanelViewModel` reference every other window observes.

Goal: each window owns its own panel state. New windows opened via Cmd+N seed at the frontmost window's paths. macOS state restoration handles bring-back-all-windows on relaunch. Bookmarks (security-scoped folder grants) move into their own store and no longer live alongside window state.

## Locked design decisions

1. **Multi-window via `WindowGroup(for: PanelSession.self)`** — SwiftUI-native. macOS automatically persists and restores each window's value.
2. **`PanelSession` shape:** `struct PanelSession: Hashable, Codable, Sendable { let id: UUID; let leftPath: String; let rightPath: String }`. UUID lets two windows on identical paths coexist.
3. **Bookmarks live in a separate `BookmarkStore`**, keyed by path. Completely decoupled from window management.
4. **Missing/stale bookmark on restore** → pass the URL constructed from the path string to `PanelViewModel` without acquired scope; existing reload error path handles it.
5. **No backstop session persistence** — trust macOS state restoration alone.
6. **Menu commands** target the focused window via a `MainCommands: Commands` struct holding `@FocusedValue(\.appState) var focused: AppState?`. Buttons are `.disabled(focused == nil)` when nothing is focused.
7. **Cmd+N "copy frontmost" scope:** paths only. Active panel side defaults to `.left`; no selection or history is carried.
8. **Do the `BookmarkStore` extraction in this PR** — drop `PanelPathStore` entirely. Pre-release app, no migration.

## Architecture

```
LCdrDataApp
 ├── @State env: AppEnvironment   (one instance — shared)
 │     ├── configuration: ConfigurationService
 │     ├── bookmarkStore: BookmarkStoreProtocol
 │     └── weak mostRecentAppState: AppState?
 │
 ├── WindowGroup(for: PanelSession.self) { $session in
 │     WindowRootView(session: $session, env: env)
 │       └── @State appState: AppState   (one per window)
 │             ├── leftPanel: PanelViewModel
 │             ├── rightPanel: PanelViewModel
 │             ├── activePanel: .left
 │             └── fileOperations: FileOperationViewModel
 │   } defaultValue: { env.makeFreshSession() }   ← Cmd+N
 │
 ├── .commands { MainCommands(env: env) }
 │     └── @FocusedValue(\.appState) focused: AppState?
 │
 └── Settings { ConfigurationView(configuration: env.configuration) }
```

## Files to change

### New: `LCdrData/Models/PanelSession.swift`
```swift
import Foundation

struct PanelSession: Hashable, Codable, Sendable {
    let id: UUID
    let leftPath: String
    let rightPath: String

    init(id: UUID = UUID(), leftPath: String, rightPath: String) {
        self.id = id
        self.leftPath = leftPath
        self.rightPath = rightPath
    }
}
```

### New: `LCdrData/Services/BookmarkStore.swift`
- Protocol: `save(url: URL)`, `resolve(path: String) -> URL?`. The `save` form captures a security-scoped bookmark from a URL the app currently has access to and persists it (UserDefaults dictionary `[path: Data]`).
- Concrete `BookmarkStore` keeps the persistence in UserDefaults under a single key (`"bookmarks"`) holding `[String: Data]`. `resolve` decodes the bookmark, calls `URL(resolvingBookmarkData:options: .withSecurityScope, ...)`, returns the URL (and acquires scope via existing `SandboxAccessService`, or returns the URL and lets the caller acquire — pick one consistent rule).
- Existing helpers in `LCdrData/Services/BookmarkService.swift` (`bookmarkData(for:)`) move/are reused by `BookmarkStore` as its low-level wrapper.
- Bookmark capture policy: every time a panel's `currentDirectory` changes successfully, call `env.bookmarkStore.save(url:)`. This keeps the store fresh for every path the user actually rests on, so restore-on-launch works even for paths deep under the originally-granted root.

### New: `LCdrData/App/AppEnvironment.swift`
```swift
import Foundation
import AppKit

@MainActor
final class AppEnvironment {
    let configuration: ConfigurationService
    let bookmarkStore: BookmarkStoreProtocol
    weak var mostRecentAppState: AppState?

    init(
        configuration: ConfigurationService = ConfigurationService(),
        bookmarkStore: BookmarkStoreProtocol = BookmarkStore()
    ) {
        self.configuration = configuration
        self.bookmarkStore = bookmarkStore
        try? configuration.load()
    }

    func makeFreshSession() -> PanelSession {
        if let frontmost = mostRecentAppState {
            return PanelSession(
                leftPath: frontmost.leftPanel.state.currentDirectory.path,
                rightPath: frontmost.rightPanel.state.currentDirectory.path
            )
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return PanelSession(leftPath: home, rightPath: home)
    }
}
```

### Rewrite: `LCdrData/App/LCdrDataApp.swift`
```swift
import SwiftUI

@main
struct LCdrDataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup(for: PanelSession.self) { $session in
            WindowRootView(session: $session, env: env)
        } defaultValue: {
            env.makeFreshSession()
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands { MainCommands(env: env) }

        Settings {
            ConfigurationView(configuration: env.configuration)
        }
    }
}

struct ActiveAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[ActiveAppStateKey.self] }
        set { self[ActiveAppStateKey.self] = newValue }
    }
}

extension Notification.Name {
    static let lcdrConfigurationApplied = Notification.Name("LCDR.configurationApplied")
}
```

### New: `LCdrData/Views/WindowRootView.swift`
- Takes `Binding<PanelSession>` and the shared `AppEnvironment`.
- `@State private var appState: AppState` initialized in `init` from the session:
  ```swift
  let leftURL = env.bookmarkStore.resolve(path: session.wrappedValue.leftPath)
               ?? URL(fileURLWithPath: session.wrappedValue.leftPath, isDirectory: true)
  let rightURL = ... // same
  _appState = State(initialValue: AppState(
      leftDirectory: leftURL,
      rightDirectory: rightURL,
      configuration: env.configuration
  ))
  env.mostRecentAppState = appState     // best-effort initial value
  ```
- Body publishes `.focusedSceneValue(\.appState, appState)`.
- Observes `NSWindow.didBecomeKeyNotification` and refreshes `env.mostRecentAppState = appState` whenever this window becomes key.
- Observes panel `currentDirectory` changes (via `.onChange(of: appState.leftPanel.state.currentDirectory)` and the same on right):
  - Writes back into `$session` so macOS state-restoration sees the latest paths.
  - Calls `env.bookmarkStore.save(url:)` so a future launch can resolve the new path.
- Observes `.lcdrConfigurationApplied` notifications and calls `appState.applyEffectiveConfiguration()`.

### New: `LCdrData/App/MainCommands.swift`
```swift
import SwiftUI

struct MainCommands: Commands {
    let env: AppEnvironment
    @FocusedValue(\.appState) private var focused: AppState?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                guard let focused else { return }
                Task { await focused.presentOpenFolderPanel() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(focused == nil)
        }

        CommandMenu("Favorites") {
            let entries = env.configuration.current.bookmarkEntries
            if entries.isEmpty {
                Button("No favorites — add in Settings") {}.disabled(true)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Button(entry.label) {
                        guard let focused else { return }
                        Task { await focused.navigateActivePanelToFavorite(path: entry.path) }
                    }
                    .disabled(focused == nil)
                }
            }
        }

        CommandGroup(after: .sidebar) { navigationButtons }
        CommandGroup(after: .pasteboard) { selectionButtons }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        // Go to Parent, Refresh, Toggle Hidden, Back, Forward, Go to Path…, Open
        // Each: guard let focused; .keyboardShortcut(...); .disabled(focused == nil)
    }

    @ViewBuilder
    private var selectionButtons: some View {
        // Copy Paths, Select All, Deselect All, Move to Trash, Delete Immediately
    }
}
```

### Trim: `LCdrData/App/AppDelegate.swift`
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
```
Save-on-quit and release-on-quit logic both go away — state restoration covers persistence; per-panel `releaseDirectorySecurityScope` (existing in `PanelViewModel`) covers scope hygiene when a panel deinits or navigates away.

### Modify: `LCdrData/ViewModels/AppState.swift`
- **Remove** the `panelPathStore` parameter from the designated init and the `panelPathStore.restore()` call. Directories are now injected by `WindowRootView`.
- **Remove** the convenience init that defaulted `panelPathStore` to `PanelPathStore()`.
- **Add** a new convenience init for tests: `convenience init()` calling the designated init with home-dir defaults and `configuration: ConfigurationService()`.
- **Remove** `savePanelPaths()` (no longer called).
- **Keep** `releasePanelSecurityScope()` — still useful even if AppDelegate no longer calls it, in case a window is closed manually.
- Make `configuration:` a required, no-default parameter on the designated init (so production code can't accidentally fork its own ConfigurationService).

### Modify: `LCdrData/Views/ConfigurationView.swift`
- Replace `@Environment(AppState.self) private var appState` with `let configuration: ConfigurationService` injected via init.
- Replace every `appState.configuration` with `configuration` (lines 101, 114, 121, 128).
- Replace `await appState.applyEffectiveConfiguration()` at line 131 with `NotificationCenter.default.post(name: .lcdrConfigurationApplied, object: nil)`.

### Modify: `LCdrData/Views/MainWindowView.swift`
- Remove `.focusedSceneValue(\.activePanel, appState.activePanelViewModel)` at line 20 — unused now that `\.appState` covers menu-command routing (grep confirms no callers).
- Update `#Preview` at line 534 to construct `AppState(leftDirectory: ..., rightDirectory: ..., configuration: ConfigurationService())` if the convenience init's signature changes — keep the test-friendly `AppState()` convenience and the preview keeps working.

### Delete: `LCdrData/Services/PanelPathStore.swift`
Replaced by `BookmarkStore` + `WindowGroup(for:)` state restoration.

### Modify: `LCdrDataTests/AppStateTests.swift`
- All `AppState()` calls (lines 42, 50, 59) keep working via the new test convenience init.
- `AppState(panelPathStore:)` call sites (lines 82, 98, 120, 134, 146): these tests exist to exercise restore-via-PanelPathStore. With `PanelPathStore` gone they no longer have a behaviour to test — either delete them or rewrite to test bookmark resolution in `WindowRootView` / `BookmarkStore` instead. Cleanest: delete those AppState-level tests and add equivalent coverage to `BookmarkStoreTests.swift`.

### Delete: `LCdrDataTests/PanelPathStoreTests.swift` (if it exists)

### New: `LCdrDataTests/BookmarkStoreTests.swift`
- Round-trip a bookmark through `save(url:) → resolve(path:) → URL`.
- Stale-bookmark resolves to `nil`.
- Resolve for an unknown path returns `nil`.
- Multiple paths stored independently.

## Critical files

- `LCdrData/App/LCdrDataApp.swift` (rewrite)
- `LCdrData/App/AppEnvironment.swift` (new)
- `LCdrData/App/AppDelegate.swift` (trim)
- `LCdrData/App/MainCommands.swift` (new)
- `LCdrData/Views/WindowRootView.swift` (new)
- `LCdrData/Models/PanelSession.swift` (new)
- `LCdrData/Services/BookmarkStore.swift` (new)
- `LCdrData/Services/PanelPathStore.swift` (delete)
- `LCdrData/Services/BookmarkService.swift` (kept; consumed by BookmarkStore)
- `LCdrData/ViewModels/AppState.swift` (trim, remove panelPathStore arg)
- `LCdrData/Views/ConfigurationView.swift` (decouple from AppState)
- `LCdrData/Views/MainWindowView.swift` (small)
- `LCdrDataTests/AppStateTests.swift` (delete the panelPathStore-restore tests)
- `LCdrDataTests/BookmarkStoreTests.swift` (new)

## Reused existing code

- `AppState` designated init (lines 18–58) — keep the shape minus `panelPathStore`.
- `AppState.applyEffectiveConfiguration()` (lines 112–121) — called per-window on `.lcdrConfigurationApplied`.
- `AppState.presentOpenFolderPanel()`, `navigateActivePanelToFavorite()`, `copySelectedPathsToPasteboard()` (lines 123–151) — still called by `MainCommands` via the focused-value AppState.
- `BookmarkService.bookmarkData(for:)` — wrapped by `BookmarkStore.save(url:)`.
- `SandboxAccessService` — already used inside `PanelViewModel`. No changes.
- `PanelViewModel.releaseDirectorySecurityScope()` — keeps doing its job per-panel.
- `FocusedValueKey` pattern (`ActivePanelKey` at `MainWindowView.swift:523-532`) is the template for the new `ActiveAppStateKey`.

## Verification (manual + tests)

After `tuist install && tuist generate`:

1. **Sync bug fixed.** Build & run. Cmd+N opens a new window. Navigate window A's left panel into `~/Documents`. Window B's left panel must remain on its previous folder. Repeat with the right panel, Cmd+Up, type-ahead, double-click — no cross-window changes.
2. **Cmd+N copies frontmost.** Navigate window A to two distinct folders. Cmd+N → new window opens at the same two folders, with active panel `.left`, no selection, no history.
3. **Two windows on the same paths coexist.** With the same paths in window A, Cmd+N twice in a row — should produce two additional windows, not focus the first one (because each PanelSession has a unique UUID).
4. **macOS state restoration.** With System Settings → General → "Close windows when quitting an app" *disabled* (the default), open three windows at distinct path pairs, Cmd+Q, relaunch. Three windows reopen at their respective paths. Bookmarked folders remain accessible (e.g., on an external drive that's still plugged in).
5. **Bookmark store handles missing/stale bookmarks.** Open Folder for `/Volumes/SD/photos`, navigate around, quit. Unplug the drive. Relaunch. The window opens; the right panel shows the existing "folder unreadable" state from `PanelViewModel`. App does not crash.
6. **Focused command targeting.** Two windows open. Focus A → Cmd+R reloads A only. Click into B → Cmd+R reloads B only. Walk every shortcut: Cmd+Shift+O (Open Folder), Cmd+L (Path bar), Cmd+Up/Down, Cmd+H (toggle hidden), Cmd+\[ / Cmd+\], Cmd+A / Cmd+Shift+A, Cmd+Option+C, Delete, Cmd+Delete. Each affects only the focused window.
7. **Settings propagation.** Two windows open. Settings → change appearance.fontSize → Apply. Both windows re-render with new size and re-list with new sort/hidden settings (the `.lcdrConfigurationApplied` notification fires `applyEffectiveConfiguration` in each `WindowRootView`).
8. **Last window closed → quit.** Close every main window. App terminates (AppDelegate keeps `applicationShouldTerminateAfterLastWindowClosed = true`).
9. **First launch.** Wipe state (`defaults delete com.xvir.LCdrData` + `~/Library/Saved Application State/com.xvir.LCdrData.savedState`). Launch. One window opens at `~/` for both panels.

Run unit tests: `tuist test "LCdrData" --skip-ui-tests`. New `BookmarkStoreTests` must pass; existing `AppStateTests` (after the panelPathStore-restore tests are deleted) must pass.
