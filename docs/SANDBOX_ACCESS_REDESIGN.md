# Sandbox access redesign + symlink folder navigation

## Context

LCdrData's sandbox-access flow has three problems that surface together when a
user navigates into a symlink-to-folder whose target lives outside any granted
folder (e.g. `~/Documents/link_to_backup → /Volumes/Backup`):

1. `BookmarkStore` exists but is **never written to and never read from**. The
   comment in `BookmarkService.swift` about access "across launches" is
   aspirational — granted access only survives the in-memory
   `SandboxAccessService.grantedURLs` set. Every relaunch starts from zero
   even if the user has already granted folders.
2. `DirectorySession.init` calls `startAccessingSecurityScopedResource()` on
   the *panel's current directory*, which is almost never a bookmarked URL —
   it is a sub-path. The call returns `false`, `hasSecurityScope` stays
   `false`, and access happens to work only by inheritance from some other
   scope or because the path is unrestricted. Symlinks to never-granted
   targets fail silently.
3. The "Grant Access" UI is embedded in each panel as a permission-error
   state. When two panels in two windows hit denials at restoration time,
   the user is presented with two stuck panels and no coordinated flow.

This redesign solves all three together. Symlink-to-folder navigation works
correctly as a side effect — Q1's orthodox display preservation matches
current code; the sandbox half is what's actually broken.

Goal: bookmarks persist between launches; first launch asks for Home folder
access once; subsequent denials use an app-modal NSAlert; navigation
behaves atomically (commit-or-revert); the embedded panel "Access Denied" UI
disappears. Symlink folders also get a Finder-style alias-badge icon.

## Locked design decisions

1. **Preserve symlink paths in panel state (orthodox style).** `PanelViewModel`
   keeps the symlink URL in `state.currentDirectory`, `state.history`, and
   breadcrumbs. Going "up" from inside a link lands the user back where the
   link lives. Matches Total Commander / Midnight Commander, not Finder.
   Current code already does this; no change to `navigate(to:)`.

2. **At-launch app-wide scope acquisition.** `AppEnvironment.start()` iterates
   `BookmarkStore`, resolves each bookmark (refreshing stale-but-resolvable
   ones), and calls `startAccessingSecurityScopedResource()` on each. Scopes
   stay active for the entire app session; `applicationWillTerminate`
   releases them. `DirectorySession` loses all scope-management code and
   becomes a pure FD watcher + lister.

3. **Single Home grant at startup, before any window opens.** If no bookmark
   in `BookmarkStore` covers `~`, present an NSAlert + NSOpenPanel pre-
   navigated to `~`. Buttons: *Grant Access…* / *Skip for Now*. Granting
   covers Documents/Desktop/Downloads/etc. as subtrees recursively. Sequential
   window restoration begins only once this prompt resolves.

4. **Skip-button silent fallback + menu re-trigger.** If the user clicks
   *Skip for Now*, the app proceeds; panels that can't list their default
   directories show an empty state (decision 8 below). A menu item
   *LCdrData → Grant Folder Access…* manually re-runs the request flow at
   any time. No persistent banner; no second persisted "didCompleteOnboarding"
   flag — the bookmark store's coverage of `~` is the source of truth.

5. **Reactive NSAlert, app-modal, owned by `AppEnvironment`.** When a
   user-initiated navigation hits a permission error, `SandboxAccessService`
   (now an `actor` hanging off `AppEnvironment`, not per-`AppState`) presents
   an app-modal NSAlert. Hybrid copy per decision 7: alert title names the
   *symlink* the user clicked; informative text discloses the *resolved
   target* that will be bookmarked. *Grant Access…* opens NSOpenPanel
   pre-navigated to the resolved target. *Cancel* leaves the panel state
   unchanged.

6. **Atomic navigation: commit or revert.** `PanelViewModel.navigate(to:)`
   snapshots `(currentDirectory, history, historyIndex, cursor)` before
   mutating. On permission error, awaits `requestAccessIfNeeded`. If
   granted → re-attempt the *original* navigation. If still denied or
   cancelled → restore the snapshot. Net effect: navigation either succeeds
   with a visible listing, or the panel is exactly where it was. History
   never lands on a denied path.

7. **Accept any grant; retry the original navigation.** The user is free to
   navigate up/down/sideways in NSOpenPanel before clicking Grant. Whatever
   they grant is saved and scope-activated; the panel then re-attempts the
   *originally requested* navigation (not the granted folder). If the grant
   covers the request → success. If not → revert per decision 6.

8. **Initial-reload denials are silent; only user-initiated navigations
   trigger the reactive alert.** A panel constructed at startup with a
   directory it can't list fails silently and renders an empty
   `FileTableView` with a small placeholder line. This avoids prompting the
   user again immediately after they declined the startup Home prompt.
   The embedded "Access Denied" panel view is gone entirely; only the
   non-permission "Failed to load directory" + Retry case remains.

9. **Per-resolved-path single-flight dedup.** If two panels simultaneously
   request access to the same resolved target, the second awaits the same
   result as the first. macOS app-modal naturally serialises the alert
   presentation across distinct targets; no explicit FIFO queue needed.

10. **Sequential window restoration.** `AppEnvironment` restores saved
    windows one at a time at launch. Each window's `firstReloadComplete`
    must resolve (both panels' initial reloads finished — succeeded, granted-
    and-retried, or cancelled-and-reverted) before the next window opens.
    Cmd+N during normal use still opens windows immediately; sequencing
    applies only to initial restoration. Eliminates the cross-window denial
    storm.

11. **Stale bookmark policy: refresh-when-possible, silent-skip-when-not.**
    `BookmarkService.url(fromBookmarkData:)` is extended to also return a
    refreshed blob when the original resolved but `bookmarkDataIsStale ==
    true`. `BookmarkStore.allBookmarkURLs()` overwrites refreshed entries
    back to UserDefaults. Unresolvable entries are pruned silently — the
    user will discover the loss the moment they navigate there and the
    reactive prompt handles it.

12. **Symlink folders show a Finder-style alias-badge icon.** Standard blue
    `folder.fill` with a small white-circle / black-arrow badge in the
    bottom-left, identical pattern (over `doc`) for symlinks-to-file. The
    current orange `arrow.triangle.turn.up.right.diamond` icon is dropped.

13. **`BookmarkStore` storage stays in `UserDefaults`.** Bookmark blobs are
    <1KB; expected count is <100. UserDefaults is fine. No file-store
    migration needed.

14. **Permissions audit/revoke UI is out of scope.** Future feature.
    The menu item from decision 4 is the entry point until then.

15. **Symlink cycle detection in listings is deferred.** Orthodox preservation
    means a user navigating into a cyclic symlink chain sees a deepening
    path and can back out via `..`. Cycle detection only matters once
    recursive operations exist (size compute, recursive copy).

## Architecture

```
AppEnvironment (one instance, app-wide)
 ├── configuration: ConfigurationService
 ├── bookmarkStore: BookmarkStoreProtocol
 ├── sandboxAccess: SandboxAccessService   ← moved here, was per-AppState
 ├── activeScopes: [URL]                   ← all scopes acquired at launch
 └── start() async
       1. bookmarkStore.allBookmarkURLs()  (refreshes stale, prunes dead)
       2. for each → startAccessingSecurityScopedResource() → activeScopes
       3. if no bookmark covers ~:
            await sandboxAccess.requestAccessIfNeeded(.startup)
            if granted: save bookmark, start scope, activeScopes.append
       4. restore saved windows sequentially:
            for snapshot in savedWindows {
                let appState = openWindow(from: snapshot)
                await appState.firstReloadComplete
            }

SandboxAccessService (actor)
 ├── inFlight: [URL: [CheckedContinuation<URL?, Never>]]   ← per-path dedup
 ├── bookmarkGranted: AsyncStream<URL>                      ← grant broadcast
 └── requestAccessIfNeeded(context: AccessRequestContext) async -> URL?
       presents NSAlert + NSOpenPanel, persists bookmark on grant,
       starts scope, registers with AppEnvironment.activeScopes,
       yields URL to bookmarkGranted stream.

AccessRequestContext (enum)
 ├── .startup
 │     alert: "Welcome to LCdrData" / "...needs access to your Home folder..."
 │     buttons: Grant Access… / Skip for Now
 │     NSOpenPanel.directoryURL = ~
 ├── .reactive(displayURL: URL, resolvedTarget: URL)
 │     alert: "Grant access to \"<displayURL.lastPathComponent>\""
 │     informative: "This folder points to <resolvedTarget.path>. ..."
 │     buttons: Grant Access… / Cancel
 │     NSOpenPanel.directoryURL = resolvedTarget
 └── .manualGrant(suggestedURL: URL)
       alert: "Grant access to a folder"
       informative: "Subfolders are covered automatically."
       buttons: Grant Access… / Cancel
       NSOpenPanel.directoryURL = suggestedURL

BookmarkStore (existing protocol, extended)
 ├── save(url:)                          (existing, now actually called)
 ├── resolve(path:) -> URL?              (existing)
 ├── allBookmarkURLs() -> [URL]          ← new; refreshes stale entries
 └── bookmarkCovering(url:) -> URL?      ← new; longest-prefix on
                                           resolved-target path

PanelViewModel
 ├── async navigate(to:)
 │     1. snapshot = (currentDirectory, history, historyIndex, cursor)
 │     2. mutate to target URL; reload(.fresh)
 │     3. on permission error (and isUserInitiated):
 │          granted = await env.sandboxAccess.requestAccessIfNeeded(
 │              .reactive(displayURL: url, resolvedTarget: url.resolvingSymlinksInPath()))
 │          if granted != nil: reload(.fresh)
 │          if still error or granted == nil: restore snapshot
 │     4. on permission error (not isUserInitiated): leave panel in
 │        empty + placeholder state; do not prompt
 ├── observes env.sandboxAccess.bookmarkGranted:
 │     if in error state and currentDirectory under granted URL → reload
 └── firstReloadComplete: Task<Void, Never>   ← awaited by sequential restore

DirectorySession
 └── (loses all scope code)
     just opens FD with O_EVTONLY and debounces change events.

PanelView
 └── errorView: only the non-permission "Failed to load directory" + Retry
     case remains. Stuck panels render an empty FileTableView with a small
     placeholder line: "No access to this folder. Press Cmd+L to navigate
     elsewhere, or grant access via LCdrData → Grant Folder Access…"

FileTableView.fileIcon
 ├── isParentDirectory                → "arrow.up.doc"
 ├── isSymlinkToDirectory             → folder.fill + aliasBadge overlay
 ├── isDirectory                      → folder.fill
 ├── isSymlink (link-to-file)         → doc + aliasBadge overlay
 └── else                             → doc
```

## Files to change

### New: `LCdrData/Services/AccessRequestContext.swift`
```swift
import Foundation

/// Describes which kind of access request is being made — startup, reactive,
/// or manual menu trigger. Determines alert copy, button labels, and the
/// initial `NSOpenPanel.directoryURL`.
enum AccessRequestContext: Sendable {
    case startup
    case reactive(displayURL: URL, resolvedTarget: URL)
    case manualGrant(suggestedURL: URL)
}
```

### Changed: `LCdrData/Services/SandboxAccessService.swift`
Convert to `actor`. Add per-resolved-path single-flight dedup map. Move
ownership from `AppState` to `AppEnvironment`. Replace
`requestAccess(to:)` with `requestAccessIfNeeded(context:) async -> URL?`.
Expose `bookmarkGranted` as an `AsyncStream<URL>`. On a successful grant,
call `bookmarkStore.save`, start scope, and notify `AppEnvironment` so
the new scope joins `activeScopes`.

Remove `grantedURLs` — its role is subsumed by `BookmarkStore`.

### Changed: `LCdrData/Services/BookmarkService.swift`
Extend `url(fromBookmarkData:)` to return both the URL and a refreshed-
data blob when the original was stale-but-resolvable:

```swift
nonisolated static func resolve(_ data: Data) -> (url: URL?, refreshed: Data?)
```

The previous `url(fromBookmarkData:)` helper stays (delegates to the new
one) for any test/legacy call sites.

### Changed: `LCdrData/Services/BookmarkStore.swift`
Implement `allBookmarkURLs() -> [URL]` — load every blob, resolve each,
overwrite the stored blob when a refresh was produced, return the resolved
URLs. Implement `bookmarkCovering(url:) -> URL?` — match the **resolved**
path of the input against every stored bookmark's resolved path, return
the longest prefix match (or `nil`).

### Changed: `LCdrData/Services/DirectorySession.swift`
Remove `hasSecurityScope`, the `startAccessingSecurityScopedResource()`
call in `init`, and the corresponding `stopAccessing…` in `cancel()`.
Scope is no longer this class's responsibility.

### Changed: `LCdrData/App/AppEnvironment.swift`
Add `let sandboxAccess: SandboxAccessService` and
`private(set) var activeScopes: [URL] = []`. Add
`func start() async` that runs the launch sequence in the architecture
diagram. Add `func releaseAllScopes()` for `applicationWillTerminate`.

### Changed: `LCdrData/ViewModels/PanelViewModel.swift`
- Inject `SandboxAccessService` via `AppEnvironment` (no longer a per-panel
  parameter from `AppState`).
- Add `isUserInitiatedNavigation: Bool` flag threaded through `navigate(to:)`
  / `navigateBack` / `navigateForward` (true) and the initial-reload path
  (false). Refreshes triggered by the directory watcher also pass `false`.
- Snapshot/restore logic in `navigate(to:)` per decision 6.
- Drop `requestAccessAndReload()` — its callers shouldn't exist any more
  (the embedded panel view is gone).
- Add `firstReloadComplete: Task<Void, Never>` set in `init`, awaited by
  sequential restoration.
- Subscribe to `env.sandboxAccess.bookmarkGranted` to retry stuck reloads
  when a new grant covers the panel's `currentDirectory`.
- Remove `isPermissionError` — error state is now binary (failed or not).

### Changed: `LCdrData/ViewModels/AppState.swift`
- Remove the per-`AppState` `SandboxAccessService` instance and its
  `injection` into each panel. Panels now take their service from
  `AppEnvironment`.
- Add `func firstReloadComplete() async` — awaits both panels'
  `firstReloadComplete` tasks.

### Changed: `LCdrData/Views/PanelView.swift`
- Drop the `isPermissionError` branch from `errorView`. The "Access Denied"
  view (lock-shield icon, "Grant Access…" button) goes away.
- Empty-state placeholder for the stuck case: when `state.items.isEmpty`
  *and* `errorMessage == nil` (because permission errors no longer set
  `errorMessage`) *and* a load completed, render a centered hint:
  "No access to this folder. Press Cmd+L to navigate elsewhere, or grant
  access via **LCdrData → Grant Folder Access…**"
- Keep the "Failed to load directory" + Retry view for non-permission
  errors.

### Changed: `LCdrData/Views/FileTableView.swift`
Reorder the `fileIcon` branches per decision 12:

```swift
@ViewBuilder
private var fileIcon: some View {
    if item.isParentDirectory {
        Image(systemName: "arrow.up.doc")
            .foregroundStyle(.secondary)
    } else if item.isSymlinkToDirectory {
        folderIcon.overlay(alignment: .bottomLeading) { aliasBadge }
    } else if item.isDirectory {
        folderIcon
    } else if item.isSymlink {
        docIcon.overlay(alignment: .bottomLeading) { aliasBadge }
    } else {
        docIcon
    }
}

private var folderIcon: some View {
    Image(systemName: "folder.fill").foregroundStyle(.blue)
}

private var docIcon: some View {
    Image(systemName: "doc").foregroundStyle(.secondary)
}

private var aliasBadge: some View {
    Image(systemName: "arrowshape.turn.up.left.circle.fill")
        .font(.system(size: 9))
        .foregroundStyle(.black, .white)   // glyph, background
        .offset(x: -1, y: 1)
}
```

Tune `9pt` and `(-1, 1)` visually before committing — these are seed values.

### Changed: `LCdrData/App/` (commands)
Add a new menu item under the app menu:

```swift
CommandGroup(after: .appInfo) {
    Button("Grant Folder Access…") {
        let suggested = focused?.activePanelViewModel.state.currentDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        Task {
            await env.sandboxAccess.requestAccessIfNeeded(
                context: .manualGrant(suggestedURL: suggested)
            )
        }
    }
}
```

Wire-up location depends on the existing `MainCommands` structure
(see `MULTIWINDOW.md` for the `@FocusedValue(\.appState)` pattern).

### Changed: window restoration in `LCdrDataApp.swift`
The `WindowGroup(for: PanelSession.self)` body must `await env.start()`
before producing its first `WindowRootView`. Inside, each window's panels
expose their `firstReloadComplete` task; the next saved window is created
only after the current one's task resolves. The current
`WindowGroup`-as-multi-window-restoration model may need a small explicit
restoration coordinator to enforce sequentiality (SwiftUI doesn't expose
a hook to control restoration order).

### Removed
- `PanelView`'s `isPermissionError` branch (file kept, view body shrinks).
- `PanelViewModel.requestAccessAndReload()` and `isPermissionError` flag.
- `SandboxAccessService.grantedURLs` (replaced by `BookmarkStore` coverage).
- `DirectorySession.hasSecurityScope` and its start/stop calls.
- The orange `arrow.triangle.turn.up.right.diamond` symlink icon path.

## Test plan

### Unit tests

#### `BookmarkStoreTests` (extend existing if present; new otherwise)
- `allBookmarkURLs_returnsResolvedURLs` — fake serializer returns valid URLs.
- `allBookmarkURLs_refreshesStaleEntries` — fake serializer returns (url,
  refreshedBlob); after the call, the new blob is persisted in UserDefaults.
- `allBookmarkURLs_prunesUnresolvableEntries` — fake serializer returns
  `nil`; entry is removed from UserDefaults.
- `bookmarkCovering_findsAncestor` — store contains `/Users/foo`; querying
  `/Users/foo/Documents` returns `/Users/foo`.
- `bookmarkCovering_findsLongestPrefix` — store contains both `/Volumes`
  and `/Volumes/Backup`; querying `/Volumes/Backup/Photos` returns
  `/Volumes/Backup`.
- `bookmarkCovering_resolvesSymlinksOnInput` — querying a symlink URL
  resolves through it and matches against bookmarks for the resolved target.
- `bookmarkCovering_returnsNilWhenNoMatch` — unrelated path.

#### `SandboxAccessServiceTests` (new)
Inject a `BookmarkStoreProtocol` mock and a presenter protocol that
replaces NSAlert + NSOpenPanel with deterministic returns.
- `requestAccess_inFlightDedup` — two concurrent calls for the same
  resolved target produce one presenter invocation; both receive the same
  result.
- `requestAccess_grant_savesBookmarkAndStartsScope` — granted URL is
  persisted to the mock store; scope-start is observable.
- `requestAccess_cancel_returnsNilWithoutPersisting` — cancelled flow
  produces `nil` and does not touch the store.
- `requestAccess_grantPublishesToStream` — `bookmarkGranted` stream emits
  the granted URL.
- `requestAccess_resolvesSymlinkForOpenPanel` — `.reactive(displayURL,
  resolvedTarget)` passes the resolved target to `NSOpenPanel.directoryURL`
  even when `displayURL` is a symlink.

#### `PanelViewModelTests` (new)
Inject a `FileSystemServiceProtocol` mock and a `SandboxAccessService`
test double.
- `navigate_success_commitsState` — happy path.
- `navigate_permissionError_userInitiated_grant_retriesAndCommits` — mock
  returns permission error first, then success on retry. Service mock
  returns granted URL. Panel ends up at target.
- `navigate_permissionError_userInitiated_cancel_revertsState` — mock
  returns permission error; service mock returns nil. Panel restored to
  pre-navigation snapshot (currentDirectory, history, cursor).
- `navigate_permissionError_initialReload_silentEmpty` — initial reload
  marked non-user-initiated; service mock asserts it was never called;
  panel ends in empty state with no error message.
- `navigateBack_permissionError_cancel_revertsForward` — history pointer
  restored on cancel.
- `bookmarkGranted_unblocksStuckPanel` — panel sits in error state;
  service emits a `bookmarkGranted` covering its currentDirectory; panel
  retries reload and commits.

#### `FileItemTests` and `FileSystemServiceTests`
No new test coverage required for the symlink work — existing tests for
`isSymlinkToDirectory` / `isNavigableDirectory` already cover the model.

### Integration / UI tests
Not in this PR. UI tests must be run manually per CLAUDE.md guidance.

## Implementation plan

Four commits, in order. Commit 4 has zero dependencies on 1–3 and can ship
separately if desired.

### Commit 1 — `refactor(sandbox): centralise scope acquisition in AppEnvironment`
- Add `allBookmarkURLs()` and `bookmarkCovering(url:)` to `BookmarkStore`.
- Add `BookmarkService.resolve(_:) -> (url, refreshed)`.
- Add `AccessRequestContext`.
- Convert `SandboxAccessService` to `actor`; move ownership to
  `AppEnvironment`; introduce `requestAccessIfNeeded`.
- Strip scope code out of `DirectorySession`.
- Add `AppEnvironment.start()` and `releaseAllScopes()`.
- Wire `LCdrDataApp` to `await env.start()` before window creation.
- Drop `SandboxAccessService` from `AppState` and `PanelViewModel`
  initialisers; route through environment.

No new UX yet — the embedded panel view still works because the catch
branch still sets `isPermissionError`. This commit is a refactor;
behaviour change is minimal.

### Commit 2 — `feat(sandbox): startup Home prompt + sequential window restoration + reactive alert redesign`
- Implement startup-Home logic in `AppEnvironment.start()` (decisions
  3, 4, 13).
- Implement sequential window restoration (decision 10) — likely a
  `WindowRestorationCoordinator` because `WindowGroup`'s restoration order
  isn't user-controllable. May restore "all at once" but suspend each
  `WindowRootView`'s panel initialisation behind a `await coordinator.next()`
  serial gate.
- Implement atomic `PanelViewModel.navigate(to:)` per decision 6.
- Add `isUserInitiatedNavigation` flag and the initial-reload silent path
  (decision 8).
- Subscribe panels to `bookmarkGranted` stream (decision 7).
- Remove `isPermissionError` from `PanelViewModel` and the embedded
  permission UI from `PanelView`. Add the empty-state placeholder.
- Add the *LCdrData → Grant Folder Access…* menu item (decision 4).

### Commit 3 — `test(sandbox): coverage of new flows`
- `BookmarkStoreTests` extensions per the test plan above.
- New `SandboxAccessServiceTests`.
- New `PanelViewModelTests` covering navigate / revert / unblock paths.

### Commit 4 — `feat(ui): symlink folders show alias-badge icon`
- Reorder branches in `FileTableView.fileIcon`.
- Extract `folderIcon` / `docIcon` / `aliasBadge` helpers.
- Visually tune the badge size and offset.

This commit is pure View; ship before or after the sandbox work.

## Out of scope

- **Full Disk Access entitlement.** Would let the app skip per-folder
  prompts entirely, but is non-sandbox-compatible and would break MAS
  distribution. Not on the table for this redesign.
- **Permissions audit/revoke UI.** A future Settings pane listing all
  granted bookmarks with revoke buttons and a `[+ Grant New Folder…]`
  button. The menu item from decision 4 is the entry point until then.
- **Symlink cycle detection in listings.** Defer until any recursive
  operation (size compute, recursive copy, recursive search) lands. The
  orthodox preserve-display behavior is already safe for casual navigation
  through cycles — the user sees the deepening path and backs out via `..`.
- **Drag-drop self-copy URL comparison.** `FileTableView.handleExternalFileDrop`
  compares `url.standardizedFileURL == dest.standardizedFileURL` to avoid
  no-op self-copies; this won't match when source and destination point to
  the same folder via different paths (one direct, one symlink). Minor;
  fix opportunistically with a `resolvingSymlinksInPath()` on both sides.
- **Bookmark storage migration to file-based store.** UserDefaults handles
  <100 bookmarks at <1KB each comfortably. Revisit if real usage outgrows it.
