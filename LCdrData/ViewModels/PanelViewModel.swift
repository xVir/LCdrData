import AppKit
import Foundation
import Observation

/// Identifies which side a panel occupies.
enum PanelSide: Sendable {
    case left
    case right
}

/// Drives a single file panel: listing, selection, navigation, and sorting.
@Observable
final class PanelViewModel {

    // MARK: - Published State

    var state: PanelState
    var isLoading: Bool = false
    var errorMessage: String?
    /// True when the last load failure was a sandbox permission denial.
    var isPermissionError: Bool = false

    /// When set, the row with this ID plays a highlight animation (fading
    /// green background). Cleared automatically after the animation ends.
    var highlightedItemID: UUID?

    /// When true, the path bar shows an editable path field (Cmd+L).
    var isPathBarEditing: Bool = false

    /// Substring filter for file names; only applied when `isFilterBarVisible` is true.
    var nameFilterText: String = ""

    /// When true, the filter bar is shown (Cmd+F) and `visibleItems` applies `nameFilterText`.
    /// Keystrokes are routed to `nameFilterText` by `MainWindowView` while visible; the list stays focused.
    var isFilterBarVisible: Bool = false

    // MARK: - Type-ahead (incremental search)

    private var typeAheadBuffer: String = ""
    private var typeAheadLastEvent: Date = .distantPast
    private let typeAheadResetInterval: TimeInterval = 1.0

    // MARK: - Dependencies

    let side: PanelSide
    private let fileSystemService: FileSystemServiceProtocol
    private let sandboxAccessService: SandboxAccessService

    // MARK: - Init

    init(
        side: PanelSide,
        initialDirectory: URL,
        fileSystemService: FileSystemServiceProtocol = FileSystemService(),
        sandboxAccessService: SandboxAccessService = SandboxAccessService()
    ) {
        self.side = side
        self.state = PanelState(currentDirectory: initialDirectory)
        self.fileSystemService = fileSystemService
        self.sandboxAccessService = sandboxAccessService
    }

    // MARK: - Directory Loading

    /// URL of a child directory to focus after the next directory load.
    /// Set before navigating to a parent so the cursor lands on the folder
    /// the user just left instead of resetting to the first item.
    private var pendingFocusChildURL: URL?

    /// Item ID to focus after the next reload, set before a delete operation
    /// so the cursor lands on the neighbouring item rather than resetting.
    private var pendingPostDeleteFocusID: UUID?

    /// Loads the contents of the current directory.
    func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        isPermissionError = false

        do {
            let items = try await fileSystemService.listDirectory(
                at: state.currentDirectory,
                showHidden: state.showHiddenFiles
            )

            let sorted = sortItems(items)

            // Prepend ".." entry unless we're at the root
            var displayItems: [FileItem] = []
            if state.currentDirectory.path != "/" {
                displayItems.append(FileItem.parentEntry(for: state.currentDirectory))
            }
            displayItems.append(contentsOf: sorted)

            state.items = displayItems

            // If we're returning from a child directory, focus that folder;
            // otherwise default to the first item.
            let targetID: UUID? = if let childURL = pendingFocusChildURL {
                displayItems.first(where: {
                    !$0.isParentDirectory && $0.isDirectory
                        && $0.url.standardizedFileURL.path == childURL.standardizedFileURL.path
                })?.id ?? displayItems.first?.id
            } else {
                displayItems.first?.id
            }
            pendingFocusChildURL = nil

            if let targetID {
                state.selectedItemIDs = [targetID]
            } else {
                state.selectedItemIDs = []
            }
            state.focusedItemID = targetID
        } catch {
            isPermissionError = SandboxAccessService.isPermissionError(error)
            errorMessage = isPermissionError
                ? "The app doesn't have permission to access this folder."
                : error.localizedDescription
            state.items = []
        }

        isLoading = false
    }

    /// Reloads the current directory while preserving the user's selection.
    /// Used for background refreshes (e.g. when the app regains focus) and
    /// after file operations where the selection should stay in place.
    ///
    /// Because `FileItem` IDs are deterministic (derived from the file URL),
    /// items that still exist keep the same UUID after a reload and SwiftUI
    /// preserves the corresponding `List` rows without flicker.  Only items
    /// that were removed need special handling: the cursor moves to the item
    /// now at the same position, or the last item if the list shrank.
    func reloadKeepingSelection() async {
        // Snapshot the current focused item ID and its index so we can
        // fall back to the same position when the focused item is removed.
        let previousFocusedID = state.focusedItemID
        let previousFocusedIndex = state.items
            .firstIndex { $0.id == previousFocusedID }
        let previousSelectedIDs = state.selectedItemIDs

        errorMessage = nil
        isPermissionError = false

        do {
            let items = try await fileSystemService.listDirectory(
                at: state.currentDirectory,
                showHidden: state.showHiddenFiles
            )

            let sorted = sortItems(items)

            var displayItems: [FileItem] = []
            if state.currentDirectory.path != "/" {
                displayItems.append(FileItem.parentEntry(for: state.currentDirectory))
            }
            displayItems.append(contentsOf: sorted)

            state.items = displayItems

            let newIDs = Set(displayItems.map(\.id))

            // If a pre-delete focus target was set and still exists, use it.
            if let pendingID = pendingPostDeleteFocusID, newIDs.contains(pendingID) {
                pendingPostDeleteFocusID = nil
                state.focusedItemID = pendingID
                state.selectedItemIDs = [pendingID]
            } else {
                pendingPostDeleteFocusID = nil

                // Keep only the selected IDs that still exist in the new listing.
                let survivingSelection = previousSelectedIDs.intersection(newIDs)

                if let previousFocusedID, newIDs.contains(previousFocusedID) {
                    // Focused item still exists — keep it focused.
                    state.focusedItemID = previousFocusedID
                    state.selectedItemIDs = survivingSelection.isEmpty
                        ? [previousFocusedID]
                        : survivingSelection
                } else if !displayItems.isEmpty {
                    // Focused item was removed without a pre-set target.
                    // Fall back to the same index position.
                    let fallbackIndex: Int
                    if let prevIndex = previousFocusedIndex {
                        fallbackIndex = min(prevIndex, displayItems.count - 1)
                    } else {
                        fallbackIndex = 0
                    }
                    let fallbackItem = displayItems[fallbackIndex]
                    state.focusedItemID = fallbackItem.id
                    state.selectedItemIDs = [fallbackItem.id]
                } else {
                    state.focusedItemID = nil
                    state.selectedItemIDs = []
                }
            }
        } catch {
            isPermissionError = SandboxAccessService.isPermissionError(error)
            errorMessage = isPermissionError
                ? "The app doesn't have permission to access this folder."
                : error.localizedDescription
            state.items = []
        }
    }

    /// Presents an open panel so the user can grant sandbox access to the
    /// current directory, then reloads if access was granted.
    func requestAccessAndReload() async {
        guard let grantedURL = await sandboxAccessService.requestAccess(
            to: state.currentDirectory
        ) else {
            return // User cancelled
        }

        // Navigate to the folder the user actually selected (may differ from
        // the originally requested one if they chose a parent).
        await navigate(to: grantedURL)
    }

    // MARK: - Navigation

    /// Items shown in the file list: full listing unless the filter bar is open, then `nameFilterText` is applied.
    var visibleItems: [FileItem] {
        guard isFilterBarVisible else { return state.items }
        return Self.filteredItems(state.items, nameFilterText: nameFilterText)
    }

    /// Navigates into a directory, pushing to history.
    func navigate(to url: URL) async {
        clearDirectoryNavigationExtras()
        // When navigating to the parent of the current directory, remember
        // the child so `loadDirectory()` can focus it after loading.
        let currentDir = state.currentDirectory
        if url.standardizedFileURL.path == currentDir.deletingLastPathComponent().standardizedFileURL.path {
            pendingFocusChildURL = currentDir
        }

        // Truncate forward history if we navigated back previously
        if state.historyIndex < state.history.count - 1 {
            state.history = Array(state.history.prefix(state.historyIndex + 1))
        }

        state.currentDirectory = url
        state.history.append(url)
        state.historyIndex = state.history.count - 1

        await loadDirectory()
    }

    /// Navigate to the parent directory.
    /// After loading the parent listing, the cursor will land on the folder
    /// we just left so the user can easily re-enter it.
    func navigateToParent() async {
        let parent = state.currentDirectory.deletingLastPathComponent()
        guard parent != state.currentDirectory else { return }
        await navigate(to: parent)
    }

    /// Navigate back in history.
    func navigateBack() async {
        guard state.historyIndex > 0 else { return }
        clearDirectoryNavigationExtras()
        state.historyIndex -= 1
        state.currentDirectory = state.history[state.historyIndex]
        await loadDirectory()
    }

    /// Navigate forward in history.
    func navigateForward() async {
        guard state.historyIndex < state.history.count - 1 else { return }
        clearDirectoryNavigationExtras()
        state.historyIndex += 1
        state.currentDirectory = state.history[state.historyIndex]
        await loadDirectory()
    }

    /// Opens a row: parent → up, directory → enter, file → default app.
    func openItem(_ item: FileItem) async {
        if item.isParentDirectory {
            await navigateToParent()
            return
        }
        if item.isDirectory {
            await navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Opens the currently selected item (Cmd+Down / double-click).
    /// Uses the List selection when exactly one item is selected; otherwise `focusedItemID`.
    func openSelectedItem() async {
        let targetID: UUID? = if state.selectedItemIDs.count == 1 {
            state.selectedItemIDs.first
        } else {
            state.focusedItemID
        }

        guard let targetID else { return }

        let item = visibleItems.first(where: { $0.id == targetID })
            ?? state.items.first(where: { $0.id == targetID })

        guard let item else { return }

        await openItem(item)
    }

    // MARK: - Sorting

    /// Changes the sort column; toggles direction if same column.
    func toggleSort(column: FileSortDescriptor.Column) async {
        state.sortDescriptor.toggle(column: column)
        await reloadCurrentListing()
    }

    /// Re-sorts and refreshes the current listing without re-fetching from disk.
    private func reloadCurrentListing() async {
        await loadDirectory()
    }

    /// Sorts items according to the current sort descriptor.
    /// Directories always appear before files.
    func sortItems(_ items: [FileItem]) -> [FileItem] {
        let descriptor = state.sortDescriptor

        return items.sorted { lhs, rhs in
            // Directories first
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            let result: ComparisonResult
            switch descriptor.column {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .size:
                let lSize = lhs.size ?? 0
                let rSize = rhs.size ?? 0
                result = lSize < rSize ? .orderedAscending
                       : lSize > rSize ? .orderedDescending
                       : .orderedSame
            case .dateModified:
                result = compareOptionalDates(lhs.modificationDate, rhs.modificationDate)
            case .dateCreated:
                result = compareOptionalDates(lhs.creationDate, rhs.creationDate)
            case .kind:
                let lKind = FileFormatter.kind(for: lhs)
                let rKind = FileFormatter.kind(for: rhs)
                result = lKind.localizedStandardCompare(rKind)
            }

            return descriptor.ascending
                ? result == .orderedAscending
                : result == .orderedDescending
        }
    }

    private func compareOptionalDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l?, r?):
            return l.compare(r)
        case (nil, .some):
            return .orderedAscending
        case (.some, nil):
            return .orderedDescending
        case (nil, nil):
            return .orderedSame
        }
    }

    // MARK: - Selection

    /// Toggles selection of a specific item.
    func toggleSelection(of itemID: UUID) {
        if state.selectedItemIDs.contains(itemID) {
            state.selectedItemIDs.remove(itemID)
        } else {
            state.selectedItemIDs.insert(itemID)
        }
    }

    /// Sets the focused item.
    func setFocused(_ itemID: UUID?) {
        state.focusedItemID = itemID
    }

    /// Selects all items (excluding ".." parent entry), respecting the name filter.
    func selectAll() {
        state.selectedItemIDs = Set(
            visibleItems
                .filter { !$0.isParentDirectory }
                .map(\.id)
        )
    }

    /// Deselects all items.
    func deselectAll() {
        state.selectedItemIDs = []
    }

    /// Collapses a multi-selection to a single focused row (Cmd+Shift+A).
    func deselectAllKeepingFocus() {
        if let id = state.focusedItemID {
            state.selectedItemIDs = [id]
        } else if let first = visibleItems.first {
            state.focusedItemID = first.id
            state.selectedItemIDs = [first.id]
        }
    }

    /// Call before a delete operation to remember which item should receive
    /// focus after the deleted items are gone.
    ///
    /// The rule: pick the next item after the last selected item. If the
    /// selected items are at the end of the list, pick the item just before
    /// the first selected item. The ".." parent entry is skipped.
    func prepareForDeletion() {
        let selectedIDs = state.selectedItemIDs
        guard !selectedIDs.isEmpty else { return }

        // Find the index range occupied by selected items (use visible order when filtered).
        let selectedIndices = visibleItems.enumerated()
            .filter { selectedIDs.contains($0.element.id) }
            .map(\.offset)

        guard let lastSelectedIndex = selectedIndices.max() else { return }

        let rowItems = visibleItems

        // Try the item right after the last selected item.
        let afterIndex = lastSelectedIndex + 1
        if afterIndex < rowItems.count {
            let candidate = rowItems[afterIndex]
            if !candidate.isParentDirectory {
                pendingPostDeleteFocusID = candidate.id
                return
            }
        }

        // All selected items are at the end — try the item before the first
        // selected item.
        guard let firstSelectedIndex = selectedIndices.min() else { return }
        let beforeIndex = firstSelectedIndex - 1
        if beforeIndex >= 0 {
            let candidate = rowItems[beforeIndex]
            if !candidate.isParentDirectory {
                pendingPostDeleteFocusID = candidate.id
                return
            }
        }

        // Fallback: focus the ".." entry if nothing else is available.
        pendingPostDeleteFocusID = rowItems.first?.id
    }

    // MARK: - Highlight

    /// Briefly highlights a row to draw the user's attention (e.g. after
    /// creating a new folder). The highlight fades out automatically.
    func highlightItem(id: UUID) {
        highlightedItemID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if highlightedItemID == id {
                highlightedItemID = nil
            }
        }
    }

    // MARK: - Hidden Files

    /// Toggles visibility of hidden files and reloads.
    func toggleHiddenFiles() async {
        state.showHiddenFiles.toggle()
        await loadDirectory()
    }

    // MARK: - Name filter

    /// Ensures focus and selection remain valid after the filter changes.
    func syncFocusAfterFilterChange() {
        let visible = visibleItems
        guard !visible.isEmpty else { return }
        if let f = state.focusedItemID, visible.contains(where: { $0.id == f }) {
            return
        }
        let first = visible.first!
        state.focusedItemID = first.id
        state.selectedItemIDs = [first.id]
    }

    /// Shows the bottom filter bar (Cmd+F). The file list keeps keyboard focus; typing is routed to `nameFilterText`.
    func showNameFilterBar() {
        isFilterBarVisible = true
    }

    /// Hides the filter bar and clears the filter string.
    func dismissNameFilterBar() {
        isFilterBarVisible = false
        nameFilterText = ""
    }

    /// Appends text to the name filter while the filter bar is visible (keyboard routing from `MainWindowView`).
    func appendToNameFilter(_ text: String) {
        guard isFilterBarVisible, !text.isEmpty else { return }
        nameFilterText += text
    }

    /// Removes one character from the filter string (Backspace / Forward Delete). Returns false if nothing was removed.
    @discardableResult
    func deleteInNameFilter(backward: Bool) -> Bool {
        guard isFilterBarVisible, !nameFilterText.isEmpty else { return false }
        if backward {
            nameFilterText.removeLast()
        } else {
            nameFilterText.removeFirst()
        }
        return true
    }

    func clearNameFilter() {
        nameFilterText = ""
    }

    // MARK: - Type-ahead

    func resetTypeAheadBuffer() {
        typeAheadBuffer = ""
        typeAheadLastEvent = .distantPast
    }

    /// Handles incremental search from printable text; returns true if focus moved.
    func handleTypeAheadInsert(_ text: String, now: Date = .now) -> Bool {
        guard !text.isEmpty else { return false }
        if now.timeIntervalSince(typeAheadLastEvent) > typeAheadResetInterval {
            typeAheadBuffer = ""
        }
        typeAheadLastEvent = now
        typeAheadBuffer.append(contentsOf: text)

        guard let matchID = Self.typeAheadMatchID(
            items: visibleItems,
            focusedID: state.focusedItemID,
            buffer: typeAheadBuffer
        ) else {
            return false
        }
        state.focusedItemID = matchID
        state.selectedItemIDs = [matchID]
        return true
    }

    // MARK: - Commander Space

    /// Toggles selection on the focused row and moves focus down one row.
    func commanderSpaceSelect() {
        let items = visibleItems
        guard let focusID = state.focusedItemID,
              let idx = items.firstIndex(where: { $0.id == focusID }) else {
            return
        }

        let row = items[idx]
        if !row.isParentDirectory {
            toggleSelection(of: focusID)
        }

        let nextIndex = idx + 1
        guard nextIndex < items.count else { return }
        let nextItem = items[nextIndex]
        state.focusedItemID = nextItem.id
        state.selectedItemIDs = [nextItem.id]
    }

    // MARK: - Home / End

    func focusFirstListItem() {
        let items = visibleItems
        guard let target = items.first(where: { !$0.isParentDirectory }) ?? items.first else {
            return
        }
        state.focusedItemID = target.id
        state.selectedItemIDs = [target.id]
    }

    func focusLastListItem() {
        let items = visibleItems
        guard let target = items.last(where: { !$0.isParentDirectory }) ?? items.last else {
            return
        }
        state.focusedItemID = target.id
        state.selectedItemIDs = [target.id]
    }

    // MARK: - Quick Look / open

    /// URL for Quick Look (F3) when a single file is selected.
    func previewURLForQuickLook() -> URL? {
        guard let item = singleSelectedNonDirectoryItem() else { return nil }
        guard !item.isDirectory else { return nil }
        return item.url
    }

    /// Opens the selected file with the default application (F4).
    func openSelectedFileWithDefaultApp() {
        guard let item = singleSelectedNonDirectoryItem() else { return }
        guard !item.isDirectory else { return }
        NSWorkspace.shared.open(item.url)
    }

    private func singleSelectedNonDirectoryItem() -> FileItem? {
        let ids = state.selectedItemIDs
        guard ids.count == 1, let id = ids.first else { return nil }
        return visibleItems.first(where: { $0.id == id && !$0.isParentDirectory })
    }

    // MARK: - Private

    private func clearDirectoryNavigationExtras() {
        isFilterBarVisible = false
        nameFilterText = ""
        resetTypeAheadBuffer()
        isPathBarEditing = false
    }

    /// Filters the full listing; keeps `..` when the filter is non-empty.
    static func filteredItems(_ items: [FileItem], nameFilterText: String) -> [FileItem] {
        let trimmed = nameFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            if item.isParentDirectory { return true }
            return item.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Next row whose name starts with `buffer` (localized), searching after `focusedID`, wrapping.
    static func typeAheadMatchID(items: [FileItem], focusedID: UUID?, buffer: String) -> UUID? {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        func matches(_ item: FileItem) -> Bool {
            if item.isParentDirectory { return false }
            return item.name.range(
                of: trimmed,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) != nil
        }

        let startAfter: Int
        if let focusedID,
           let idx = items.firstIndex(where: { $0.id == focusedID }) {
            startAfter = idx
        } else {
            startAfter = -1
        }

        if startAfter + 1 < items.count {
            for i in (startAfter + 1)..<items.count where matches(items[i]) {
                return items[i].id
            }
        }
        for i in 0...min(startAfter, items.count - 1) where matches(items[i]) {
            return items[i].id
        }
        return nil
    }
}
