# Multi-tab support in file panels

This document turns the feature request in GitHub issue #5 into a product-level design for LCdrData.

## Summary

Add a tab bar to each panel so the left and right panes can each keep multiple directories open at once. Tabs are per-panel, independent, and persist across relaunches. Each panel keeps its own active tab, navigation history, view settings, and selection state while also sharing the same dual-pane file-operation model.

The result should feel like a native macOS tabbed file browser: fast tab creation, intuitive switching, reorderable tabs, and minimal surprise when working in the dual-pane layout.

## Goals

- Let each panel keep several locations open at the same time.
- Preserve the current dual-pane workflow without making file operations more confusing.
- Match macOS tab conventions closely enough that the feature feels native.
- Keep keyboard-first use intact, especially when one panel is active and the other is the destination.
- Restore tabs and panel state correctly after relaunch.

## Non-goals

- A single global tab strip shared by both panels.
- Tabs that span windows or share state across panels.
- Full Finder-style tab container features such as pinned tabs, tab groups, or tab sessions that persist outside the app.
- Adding a new file operation model; the feature should mostly be a state-management and UI shell around the current panel architecture.

## Product principles

1. Each panel is independently tabbed.
2. Keys act on the focused panel only.
3. Tabs behave like native macOS tabs: the user sees one live file list at a time, and the active tab is the only one that actively updates its contents.
4. Selection and scroll position are preserved when switching tabs.
5. State persistence is best-effort but must be durable enough for relaunch continuity.

---

## User experience

### Panel-level tab bar

Each panel gets a macOS-style tab bar at the top of its file area. The tab bar is shown only when there is more than one tab. When the last tab is closed, the tab bar disappears and the panel returns to its single-location state.

The tab bar:

- uses a translucent native macOS appearance,
- aligns with the toolbar / app chrome conventions,
- shows a centered folder name in each tab,
- truncates with end ellipsis when the path is long,
- supports hover affordances including an inline close button aligned to the left,
- supports middle-click close,
- supports drag-and-drop reorder inside a panel,
- supports dragging a tab from one panel to the other panel.

The active tab is visually highlighted and is the tab used as the default source and destination context for the panel.

### Tab creation and activation

- `⌘T` creates a new tab in the active panel.
- The new tab duplicates the current tab's directory and current view mode.
- The newly created tab becomes active.
- `^⇥` moves to the next tab in the active panel.
- `^⇧⇥` moves to the previous tab in the active panel.
- `⌘1` through `⌘9` switches directly to a numbered tab when the panel has focus.
- Clicking a tab activates it.
- Clicking the panel body while the panel is focused does not create or change tabs.

### Tab closing

- `⌘W` closes the active tab in the active panel.
- Hovering a tab reveals an inline close button on the left side.
- Middle-click closes the tab.
- The last tab cannot be closed; the tab bar hides and the panel stays alive with its sole remaining tab.
- Closing a tab keeps the panel in a valid state: if there are remaining tabs, the active tab is selected; otherwise the panel remains on that lone tab.

### Context menu and quick actions

A right-click on a tab exposes:

- New Tab
- Close Tab
- Close Other Tabs
- Close Tabs to the Right
- Copy Path

The context menu is panel-local and acts only on the tab under the pointer.

---

## Interaction model

### Independent per-panel tabs

The left and right panels do not share a tab collection. A tab created in the left panel remains on the left panel; a tab dragged to the opposite panel moves there and becomes part of that panel's local collection.

This keeps the mental model simple:

- left panel uses its own tabs,
- right panel uses its own tabs,
- file operations remain dual-pane and are based on the active panel plus the inactive panel as destination.

### File-operation rule

The default destination for F5/F6 remains the active tab of the opposite panel.

That means:

- the app still has a single active panel,
- the user can switch tabs inside the inactive panel without changing the active panel,
- a copy or move operation targets the currently active tab in the other panel, as required.

This preserves the existing command model while allowing each panel to maintain independent workspaces.

### Selection and scroll preservation

Switching tabs must preserve the per-tab UI state rather than resetting the panel to a generic empty or default view.

Only the active tab should own the live file list. Inactive tabs keep their location, cached listing, view settings, and UI state, but they do not actively refresh in the background. When the user switches to a tab, that tab becomes active and its file list is loaded or refreshed at that point.

For each tab, preserve:

- scroll offset,
- focused row / selection state,
- sort descriptor,
- list columns and widths,
- hidden-file state,
- any panel-specific view mode, such as list/icons/columns if supported by the panel.

There is no requirement that the user sees the exact same row selection when the tab is reopened later, but it should feel stable and predictable while the tab is active.

---

## Data model

Tab support belongs in the panel state, not in the app-level window state. The panel should own a tab list and an active index.

The likely value-model shape is:

```swift
struct PanelTab: Identifiable, Hashable, Sendable {
    let id: UUID
    let location: BrowseLocation
    let title: String
    let viewMode: PanelViewMode
    let scrollOffset: CGFloat?
    let selectionState: SelectionState
    let sortDescriptor: FileSortDescriptor
    let columns: [ColumnState]
    var cachedListing: [FileItem]?
}

struct PanelTabsState {
    var tabs: [PanelTab]
    var activeTabIndex: Int
}
```

A panel's live state should be the composition of:

- the currently active tab,
- the tab collection,
- the current panel view model that is bound to the active tab,
- reload and navigation logic that applies to the active tab only.

Only the active tab should automatically update its file list. Inactive tabs may retain a cached listing and last-known state, but they are not considered live until they become active. This matches native macOS tab behavior and avoids unnecessary reload churn.

The app must avoid a model where selecting a different tab mutates a single global `currentDirectory`; that would make the system brittle and would prevent independent history and scroll state.

### Why this model is necessary

The current panel model already treats the panel as a live browsing surface with state. Tabs are best represented as a small collection of panel snapshots, each with its own current location and presentation state, rather than as a single mutable location plus a separate stack of history entries.

This will make:

- property restoration simpler,
- drag reorder easier,
- per-tab selection and scrolling straightforward,
- persistence mapping explicit and testable.

### Source of truth

The source of truth should live on `PanelState` or its equivalent, not in the view layer. The tab bar is a view of that source of truth; it should not reconstruct tab state from UI internals.

### Architecture boundary

Tabs extend the existing panel abstraction; they do not introduce a second navigation stack or a second file-operation system.

- `PanelState` owns the ordered tab collection and the active tab identity/index.
- Each `PanelTab` owns the location and the state that must survive tab switches: navigation history, sort and view settings, cursor/selection, and scroll position.
- `PanelViewModel` remains the owner of loading and mutation behavior. It snapshots the current live view into the active `PanelTab` before switching, then activates the destination tab and refetches its location.
- The panel view renders only the active tab's listing. The tab bar reads and mutates the tab collection but does not load directories directly.
- `AppState.activePanel` remains the only cross-panel focus concept. File commands resolve the source from the active panel's active tab and the destination from the inactive panel's active tab.
- `PanelSessionStore` persists both panels' tab collections and active tab identities. It is an adapter around the existing session persistence, not a new configuration file or global tab store.

The lifecycle is therefore:

```text
user action
  -> AppState.activePanel
  -> PanelViewModel
  -> snapshot active PanelTab
  -> mutate PanelState.tabs / activeTab
  -> refetch the newly active location
  -> restore its cursor, selection, sorting, and scroll state
  -> render one live listing
```

When a tab is inactive, its watcher and live listing are suspended. When it becomes active, `PanelViewModel` recreates the location session, refetches the directory, and restores the tab's saved UI state against the fresh listing. This keeps external filesystem updates visible when the user returns without causing background reloads for hidden tabs.

### Example implementation sketch

```swift
import Foundation

struct PanelTab: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let location: BrowseLocation
    var viewMode: PanelViewMode
    var sortDescriptor: FileSortDescriptor
    var hiddenFiles: Bool
    var scrollOffset: CGFloat?
    var selection: SelectionState
    var columns: [ColumnState]
    var cachedListing: [FileItem]?
}

@MainActor
struct PanelTabsState {
    var tabs: [PanelTab]
    var activeIndex: Int

    var activeTab: PanelTab? {
        guard tabs.indices.contains(activeIndex) else { return nil }
        return tabs[activeIndex]
    }
}

@MainActor
final class PanelViewModel {
    private var tabsState = PanelTabsState(tabs: [], activeIndex: 0)

    func switchToTab(_ index: Int) async {
        guard tabsState.tabs.indices.contains(index) else { return }

        let previous = tabsState.activeIndex
        tabsState.activeIndex = index

        let tab = tabsState.tabs[index]
        if tab.cachedListing == nil {
            let listing = await fileSystemService.list(location: tab.location)
            tabsState.tabs[index].cachedListing = listing
        }

        // Rebind the view model to the active tab; only this tab is considered live.
        renderActiveTab(from: previous, to: index)
    }
}
```

This keeps the tab collection as the source of truth while allowing the panel view model to render only the currently active tab.

---

## Lifecycle behavior

### Creating a tab

When `⌘T` is invoked on the active panel:

1. read the active tab's current location and view state,
2. create a new tab entry with the same directory and identical preserved view settings,
3. insert it adjacent to the active tab or after it depending on the desired macOS pattern,
4. set the new tab as active,
5. refresh the panel model to render the new location.

If the app currently shows an empty or invalid state, the new tab should fall back to the current panel's persisted location and a safe default view.

```swift
@MainActor
func newTabFromActivePanel() async {
    guard let active = tabsState.activeTab else { return }

    let clone = PanelTab(
        id: UUID(),
        title: active.title,
        location: active.location,
        viewMode: active.viewMode,
        sortDescriptor: active.sortDescriptor,
        hiddenFiles: active.hiddenFiles,
        scrollOffset: active.scrollOffset,
        selection: active.selection,
        columns: active.columns,
        cachedListing: active.cachedListing
    )

    let index = tabsState.activeIndex + 1
    tabsState.tabs.insert(clone, at: index)
    tabsState.activeIndex = index

    await reloadActiveTab()
}
```

### Switching tabs

Switching tabs updates the active index and rebinds the panel to the selected tab's state. Only the active tab should update its file list, and that refresh happens as part of switching to that tab. The operation must not materially disturb the user’s current active panel selection other than to show the selected tab's current listing.

The operation should be transaction-like:

- freeze current UI state of old tab,
- activate new tab,
- restore new tab state,
- refresh the newly active tab's listing at switch time,
- leave inactive tabs alone until they become active again.

### Closing tabs

When a tab is closed:

- if it is the last tab, keep the panel alive with the remaining content and hide the tab bar,
- if it is the active tab, activate the nearest surviving tab using the macOS convention (the tab to the right if present, otherwise the left),
- if a tab is not active, close it without changing the active tab.

The close action should be guarded against invalid state and should never leave the panel with a missing active tab index.

```swift
@MainActor
func closeTab(at index: Int) async {
    guard tabsState.tabs.count > 1 else { return }

    let oldActive = tabsState.activeIndex
    tabsState.tabs.remove(at: index)

    if index == oldActive {
        let nextIndex = min(index, tabsState.tabs.count - 1)
        tabsState.activeIndex = nextIndex
        await reloadActiveTab()
    } else if index < oldActive {
        tabsState.activeIndex -= 1
    }
}
```

### Reordering tabs

Dragging a tab inside the same panel reorders the tab collection. The active index is updated to reflect the moved tab if necessary.

The reorder must preserve:

- the tab identity,
- all per-tab view state,
- all persisted tab metadata.

### Moving a tab across panels

A tab dragged from the left panel to the right must be removed from the source panel and inserted into the destination panel.

The move operation should preserve:

- the tab's location,
- its scroll and selection state,
- its view settings,
- whether it was active at the time of movement.

If the source panel becomes empty, the tab bar hides and the panel remains in a valid state.

---

## State persistence

Tabs must be saved across app relaunches.

```swift
struct PersistedPanelTabs: Codable {
    let tabs: [PersistedTab]
    let activeIndex: Int
}

struct PersistedTab: Codable {
    let id: UUID
    let path: String
    let title: String
    let viewMode: String
    let sortOrder: String
    let hiddenFiles: Bool
    let focusRowID: String?
}

@MainActor
func persistTabs() {
    let payload = PersistedPanelTabs(
        tabs: tabsState.tabs.map { tab in
            PersistedTab(
                id: tab.id,
                path: tab.location.persistentDirectory.path,
                title: tab.title,
                viewMode: String(describing: tab.viewMode),
                sortOrder: String(describing: tab.sortDescriptor),
                hiddenFiles: tab.hiddenFiles,
                focusRowID: tab.selection.focusedID?.uuidString
            )
        },
        activeIndex: tabsState.activeIndex
    )

    defaults.set(try? JSONEncoder().encode(payload), forKey: "leftPanelTabs")
}
```

### Persisted data

For each panel, persist:

- ordered tab list,
- active tab index,
- each tab's path or location identifier,
- each tab's view mode,
- each tab's sort descriptor,
- each tab's hidden-file state,
- each tab's scroll and selection state.

The persisted representation should be panel-local and should not store transient ephemeral UI data such as animation state or hover state.

### Storage location

Use the app's existing persisted session/store pattern rather than adding a second ad-hoc configuration layer. The most natural fit is the same window/session persistence infrastructure that already records the current panel directories and restores them on relaunch.

The design should prefer a small, explicit value object for panel tabs, stored through `UserDefaults` or an equivalent app-specific store, with a clear versioned payload so future tab features can evolve without breaking existing sessions.

### Archive / virtual location handling

The app already distinguishes between real directories and archive-backed locations. Tabs must follow the same policy:

- a real directory tab can be persisted directly,
- an archive-backed tab should persist only the containing directory, not the interior entry, because the app does not reopen into a zip interior after launch,
- the active tab should not be restored into an invalid location.

This is consistent with the app's existing session model and avoids reestablishing stale archive state on launch.

### Restore semantics

On startup:

1. load the saved tab state for the left panel,
2. load the saved tab state for the right panel,
3. validate each tab path,
4. discard invalid paths or replace them with a safe fallback,
5. open the last active tab for each panel,
6. if no tabs exist, default to the last known directory or home directory.

If only one tab exists, the tab bar hides and the panel remains in single-location mode.

---

## Keyboard behaviour

Keyboard actions must be panel-local and focused-panel aware.

### Global rules

- `⌘T` creates a tab in the active panel.
- `⌘W` closes the active tab in the active panel.
- `^⇥` and `^⇧⇥` switch tabs in the active panel.
- `⌘1`–`⌘9` switch to direct tabs in the active panel.
- other shortcuts continue to target existing app-level actions and do not accidentally trigger in the inactive panel.

### Focus management

The current app has a single active panel concept. Tabs should not add a second notion of focus. A focused panel is still the panel receiving keyboard commands. The tab bar only reacts to pointer and selection events on that panel.

This preserves the app's mental model:

- one panel is active,
- the active panel owns tab actions,
- the inactive panel is the destination for panel-to-panel operations.

### Rejected behaviour

Rejection: a single keyboard shortcut affecting both panels at once. The app is a dual-pane tool, not a global tabbed browser.

Rejection: letting a tab move to the opposite panel without also changing the active panel context. The panel-owned tab model must not make the panel selection ambiguous.

---

## UI details

### Tab bar visual design

The tab bar should approximate native macOS tab styling:

- standard vibrancy / translucency,
- strong active-tab highlight,
- inactive tabs subtly dimmed,
- a consistent height matching the rest of the panel chrome,
- folder name centered within each tab,
- text truncation with end ellipsis,
- close button aligned to the left to preserve readable center text.

### Tab titles

Tab title should be the folder name, not the full path. The full path is available in the path bar or context menu.

Examples:

- `Documents`
- `Projects`
- `FolderNa...`

For path bars and copy-path actions, use the full path it currently represents.

### Context menu content

Right-click menu items should operate on the tab that was right-clicked and should not accidentally affect the opposite panel. This is especially important when both panels are visible and the user is interacting with the tab strip of one side.

---

## Implementation concept

The tab feature should be built as a small overlay on the existing panel abstraction rather than a new parallel navigation system.

### Minimal integration points

1. Add a panel-local `TabCollection` state object.
2. Make the active panel reference an `activeTabIndex` along with the live tab list.
3. Update panel reload/navigation so only the active tab owns the live file list and refreshes when that tab becomes active.
4. Update the panel UI to render a tab bar and selection state.
5. Update keyboard handling so tab actions are routed to the active panel only.
6. Persist the tab state according to session restoration rules.

The existing command path must remain explicit:

```swift
func destinationForFileOperation() -> BrowseLocation? {
    guard let sourcePanel = appState.activePanel,
          let destinationPanel = appState.activePanel.opposite,
          let source = panelState[sourcePanel].activeTab,
          let destination = panelState[destinationPanel].activeTab else {
        return nil
    }

    fileOperationCoordinator.begin(source: source.location, destination: destination.location)
    return destination.location
}
```

The coordinator should receive locations, not tab indices. A tab index is only meaningful inside its owning panel and can change during reorder or cross-panel transfer.

### Data flow

A simplified flow is:

```text
keyboard event
  -> AppState.activePanel
  -> PanelTabController
  -> active panel tab collection
  -> selected tab is activated or mutated
  -> PanelViewModel reloads / rebinds / rerenders
```

The tab layer should not bypass the existing `PanelState` / `PanelViewModel` architecture; it should sit on top of it and provide a richer browsing surface with a stable active tab index.

---

## Edge cases and risk areas

### Empty panel and last-tab close

The panel must never be left in a broken state when the final tab is closed. The app must keep a valid fallback tab or a visible single-location state even after the tab bar disappears.

### Tab state after external filesystem changes

If the directory behind a tab is renamed or removed externally, the tab should reload to a valid state and should not silently continue pointing to a stale location. This is especially important for tabs representing folders outside the sandbox.

### Dragging across panels while active tab is changed

The move operation must update both panel state collections correctly and not leave the destination panel with an invalid active index.

### Duplicate locations

Duplicate tabs for the same directory are permitted by design. The app should not merge them automatically; a tab is a browsing context, not a normalized path entry.

### Very long folder names

Long names must truncate at the tab level without making the close button or active highlight misalign. This is a visual correctness problem more than a data problem and should be tested in a UI pass after the model is in place.

### Persistence failure

If tab persistence fails or a saved path no longer exists, the app should recover gracefully and fall back to the previous valid directory rather than crashing or leaving a blank panel.

---

## Acceptance criteria mapping

The issue acceptance criteria map directly to the design above:

- Users can open, switch, reorder, and close tabs independently in both left and right panels.
- Keyboard shortcuts execute only on the active/focused panel.
- Tab switching preserves scroll position, item selections, and sort order.
- Dual-panel file copy and move target the active tab of the opposite panel.
- Open tabs and states restore correctly after app relaunch.

---

## Recommended implementation order

1. Model the panel tab collection and active index.
2. Add the tab bar UI and tab creation / switching controls.
3. Add close, close-other, and right-click menu actions.
4. Add reorder and cross-panel drag transfer.
5. Add persistence and relaunch restore.
6. Validate keyboard behavior and dual-pane operations.
7. Verify edge cases around last-tab close, invalid saved paths, and external directory changes.

This sequence keeps the work incremental and testable while maintaining a clean path from model to UI.

## Decision summary

- Native per-panel tabs, not a shared tab strip.
- Each panel owns its own tab collection, active tab index, and view state.
- `⌘T`, `⌘W`, tab switching, and direct number selection all apply to the active panel.
- F5/F6 still target the opposite panel's active tab.
- Tabs persist per panel and restore on relaunch with fallback behavior for invalid locations.

This fits the app’s current architecture and stays aligned with the macOS file-manager expectations the project already targets.
