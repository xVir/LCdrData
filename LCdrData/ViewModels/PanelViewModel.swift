import AppKit
import Foundation
import Observation
import Models
import Formatting
import Services

/// Identifies which side a panel occupies.
package enum PanelSide: Sendable {
    case left
    case right

    /// Stable token embedded in accessibility identifiers so UI tests can
    /// address one panel's elements unambiguously.
    package var identifier: String {
        switch self {
        case .left: "left"
        case .right: "right"
        }
    }
}

/// Drives a single file panel: listing, selection, navigation, and sorting.
@Observable
package final class PanelViewModel {

    // MARK: - Published State

    package var state: PanelState
    package var isLoading: Bool = false
    package var errorMessage: String?
    /// True when the last load failure was a sandbox permission denial.
    package var isPermissionError: Bool = false

    /// When set, the row with this ID plays a highlight animation (fading
    /// green background). Cleared automatically after the animation ends.
    package var highlightedItemID: UUID?

    /// When true, the path bar shows an editable path field (Cmd+L).
    package var isPathBarEditing: Bool = false

    // MARK: - Type-ahead (incremental search)

    private var typeAheadBuffer: String = ""
    private var typeAheadLastEvent: Date = .distantPast
    private let typeAheadResetInterval: TimeInterval = 1.0

    // MARK: - Dependencies

    package let side: PanelSide
    private let fileSystemService: FileSystemServiceProtocol
    private let sandboxAccessService: SandboxAccessService
    private let directoryWatchingEnabled: Bool

    // MARK: - Init

    package init(
        side: PanelSide,
        initialDirectory: URL,
        sortDescriptor: FileSortDescriptor? = nil,
        showHiddenFiles: Bool? = nil,
        directoryWatchingEnabled: Bool = false,
        fileSystemService: FileSystemServiceProtocol = FileSystemService(),
        sandboxAccessService: SandboxAccessService = SandboxAccessService(
            presenter: NoopAccessPresenter(),
            bookmarkStore: BookmarkStore()
        )
    ) {
        self.side = side
        self.directoryWatchingEnabled = directoryWatchingEnabled
        self.state = PanelState(
            currentDirectory: initialDirectory,
            sortDescriptor: sortDescriptor ?? FileSortDescriptor(column: .name, ascending: true),
            showHiddenFiles: showHiddenFiles ?? false
        )
        self.fileSystemService = fileSystemService
        self.sandboxAccessService = sandboxAccessService
    }

    // MARK: - Directory Loading

    /// The panel's grip on its current directory: holds security-scoped
    /// access, watches the FD, and debounces background reloads. Replaced
    /// (not mutated) every time the panel navigates to a new URL.
    private var currentSession: DirectorySession?

    /// Fetches a fresh listing for the panel's current directory and
    /// repositions the cursor according to `intent`. The single canonical
    /// load path — every navigation, refresh, and file-operation completion
    /// goes through here.
    package func reload(_ intent: Cursor.Intent) async {
        isLoading = true
        errorMessage = nil
        isPermissionError = false

        let previousListing = state.items
        let previousCursor = state.cursor

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
            state.cursor = Cursor.resolve(
                intent: intent,
                listing: displayItems,
                previousListing: previousListing,
                previousCursor: previousCursor
            )
            adoptDirectorySession()
        } catch {
            isPermissionError = SandboxAccessService.isPermissionError(error)
            errorMessage = isPermissionError
                ? "The app doesn't have permission to access this folder."
                : error.localizedDescription
            state.items = []
            currentSession = nil
        }

        isLoading = false
    }

    /// File URLs for the current selection excluding the parent (`..`) entry.
    package func selectedNonParentURLs() -> [URL] {
        state.items
            .filter { state.cursor.selected.contains($0.id) && !$0.isParentDirectory }
            .map(\.url)
    }

    /// Releases the panel's session — security scope and watcher are torn down.
    /// Called from the app delegate's `applicationWillTerminate`.
    package func releaseDirectorySecurityScope() {
        currentSession?.cancel()
        currentSession = nil
    }

    /// Replaces `currentSession` with a fresh one for the panel's directory.
    /// The old session's `deinit` releases scope and cancels the watcher.
    /// Background fs changes trigger a reload through the same path used after
    /// file operations.
    private func adoptDirectorySession() {
        guard directoryWatchingEnabled else {
            currentSession = nil
            return
        }
        let url = state.currentDirectory
        if let session = currentSession,
           session.url == url {
            return
        }
        currentSession = DirectorySession(url: url) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reload(.keepSelection)
            }
        }
    }

    // MARK: - Navigation

    /// Items shown in the file list (same as `state.items`; kept for call sites).
    package var visibleItems: [FileItem] { state.items }

    /// Navigates into a directory, pushing to history. On permission error
    /// the panel offers the user the reactive grant prompt; if access isn't
    /// granted the navigation is atomically reverted to the prior state.
    package func navigate(to url: URL) async {
        clearDirectoryNavigationExtras()

        let currentDir = state.currentDirectory
        let intent: Cursor.Intent
        if url.standardizedFileURL.path == currentDir.deletingLastPathComponent().standardizedFileURL.path {
            intent = .landOnChild(currentDir)
        } else {
            intent = .fresh
        }

        await performAtomicNavigation(intent: intent, displayURL: url) {
            // Truncate forward history if we navigated back previously
            if self.state.historyIndex < self.state.history.count - 1 {
                self.state.history = Array(self.state.history.prefix(self.state.historyIndex + 1))
            }
            self.state.currentDirectory = url
            self.state.history.append(url)
            self.state.historyIndex = self.state.history.count - 1
        }
    }

    /// Mutates state via `mutate`, reloads, and on permission failure offers
    /// the reactive grant prompt; if access still isn't granted, restores the
    /// pre-mutation snapshot atomically (panel behaves as if `mutate` never ran).
    private func performAtomicNavigation(
        intent: Cursor.Intent,
        displayURL: URL,
        mutate: () -> Void
    ) async {
        let snapshot = NavigationSnapshot(
            currentDirectory: state.currentDirectory,
            history: state.history,
            historyIndex: state.historyIndex,
            cursor: state.cursor
        )

        mutate()
        await reload(intent)

        guard isPermissionError else { return }

        let granted = await sandboxAccessService.requestAccessIfNeeded(
            context: .reactive(
                displayURL: displayURL,
                resolvedTarget: displayURL.resolvingSymlinksInPath()
            )
        )
        if granted != nil {
            await reload(intent)
        }

        if isPermissionError {
            state.currentDirectory = snapshot.currentDirectory
            state.history = snapshot.history
            state.historyIndex = snapshot.historyIndex
            state.cursor = snapshot.cursor
            await reload(.keepSelection)
        }
    }

    private struct NavigationSnapshot {
        let currentDirectory: URL
        let history: [URL]
        let historyIndex: Int
        let cursor: Cursor
    }

    /// Navigate to the parent directory.
    /// After loading the parent listing, the cursor will land on the folder
    /// we just left so the user can easily re-enter it.
    package func navigateToParent() async {
        let parent = state.currentDirectory.deletingLastPathComponent()
        guard parent != state.currentDirectory else { return }
        await navigate(to: parent)
    }

    /// Navigate back in history. On permission denial of the back-target,
    /// the navigation reverts atomically.
    package func navigateBack() async {
        guard state.historyIndex > 0 else { return }
        clearDirectoryNavigationExtras()
        let target = state.history[state.historyIndex - 1]
        await performAtomicNavigation(intent: .fresh, displayURL: target) {
            self.state.historyIndex -= 1
            self.state.currentDirectory = target
        }
    }

    /// Navigate forward in history. On permission denial of the forward-target,
    /// the navigation reverts atomically.
    package func navigateForward() async {
        guard state.historyIndex < state.history.count - 1 else { return }
        clearDirectoryNavigationExtras()
        let target = state.history[state.historyIndex + 1]
        await performAtomicNavigation(intent: .fresh, displayURL: target) {
            self.state.historyIndex += 1
            self.state.currentDirectory = target
        }
    }

    /// Opens a row: parent → up, directory → enter, file → default app.
    package func openItem(_ item: FileItem) async {
        if item.isParentDirectory {
            await navigateToParent()
            return
        }
        if item.isNavigableDirectory {
            await navigate(to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Opens the currently selected item (Cmd+Down / double-click).
    /// Uses the List selection when exactly one item is selected; otherwise the cursor focus.
    package func openSelectedItem() async {
        let targetID: UUID? = if state.cursor.selected.count == 1 {
            state.cursor.selected.first
        } else {
            state.cursor.focused
        }

        guard let targetID else { return }

        let item = visibleItems.first(where: { $0.id == targetID })
            ?? state.items.first(where: { $0.id == targetID })

        guard let item else { return }

        await openItem(item)
    }

    // MARK: - Sorting

    /// Changes the sort column; toggles direction if same column.
    package func toggleSort(column: FileSortDescriptor.Column) async {
        state.sortDescriptor.toggle(column: column)
        await reloadCurrentListing()
    }

    /// Re-sorts and refreshes the current listing without re-fetching from disk.
    private func reloadCurrentListing() async {
        await reload(.keepSelection)
    }

    /// Sorts items according to the current sort descriptor.
    /// Directories always appear before files.
    package func sortItems(_ items: [FileItem]) -> [FileItem] {
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
    package func toggleSelection(of itemID: UUID) {
        if state.cursor.selected.contains(itemID) {
            state.cursor.selected.remove(itemID)
        } else {
            state.cursor.selected.insert(itemID)
        }
    }

    /// Sets the focused item.
    package func setFocused(_ itemID: UUID?) {
        state.cursor.focused = itemID
    }

    /// Reacts to user-driven selection changes from the file list (clicks,
    /// arrow keys, Cmd-click). Routed through `Cursor.userDidSelect` so that
    /// rules like "empty selection restores from focused" live on the cursor.
    package func cursorDidChangeSelection(to newSelection: Set<UUID>) {
        let previous = state.cursor
        state.cursor.userDidSelect(newSelection)

        if newSelection.isEmpty, state.cursor == previous, !previous.selected.isEmpty {
            resyncSelectionAfterEmptyClick()
        }
    }

    /// Clicking blank space makes the list drop its own selection before it
    /// reports the empty set. `userDidSelect` puts the focused row straight
    /// back, so the binding ends up at the value SwiftUI already believes it
    /// published — nothing is written back down and the row stays unhighlighted
    /// even though the cursor still points at it. Publishing the empty state the
    /// list is really showing, then restoring it a runloop turn later, makes the
    /// value change for real so the row lights up again.
    private func resyncSelectionAfterEmptyClick() {
        let restored = state.cursor.selected
        state.cursor.selected = []
        Task { @MainActor in
            guard state.cursor.selected.isEmpty else { return }
            state.cursor.selected = restored
        }
    }

    /// Selects all items (excluding ".." parent entry).
    package func selectAll() {
        state.cursor.selectAll(in: visibleItems)
    }

    /// Deselects all items.
    package func deselectAll() {
        state.cursor.selected = []
    }

    /// Collapses a multi-selection to a single focused row (Cmd+Shift+A).
    package func deselectAllKeepingFocus() {
        state.cursor.deselectAllKeepingFocus(in: visibleItems)
    }

    // MARK: - Highlight

    /// Briefly highlights the row matching `url` in the current listing — used
    /// after rename / mkdir to draw the user's eye to the new item.
    /// No-op if no row in the current listing maps to that URL.
    package func highlight(url: URL) {
        let standardized = url.standardizedFileURL.path
        guard let item = visibleItems.first(where: {
            !$0.isParentDirectory
                && $0.url.standardizedFileURL.path == standardized
        }) else { return }

        highlightedItemID = item.id
        let id = item.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if highlightedItemID == id {
                highlightedItemID = nil
            }
        }
    }

    // MARK: - Hidden Files

    /// Toggles visibility of hidden files and reloads.
    package func toggleHiddenFiles() async {
        state.showHiddenFiles.toggle()
        await reload(.keepSelection)
    }

    // MARK: - Type-ahead

    package func resetTypeAheadBuffer() {
        typeAheadBuffer = ""
        typeAheadLastEvent = .distantPast
    }

    /// Handles incremental search from printable text; returns true if focus moved.
    package func handleTypeAheadInsert(_ text: String, now: Date = .now) -> Bool {
        guard !text.isEmpty else { return false }
        if now.timeIntervalSince(typeAheadLastEvent) > typeAheadResetInterval {
            typeAheadBuffer = ""
        }
        typeAheadLastEvent = now
        typeAheadBuffer.append(contentsOf: text)

        guard let matchID = Self.typeAheadMatchID(
            items: visibleItems,
            focusedID: state.cursor.focused,
            buffer: typeAheadBuffer
        ) else {
            return false
        }
        state.cursor = Cursor(focused: matchID, selected: [matchID])
        return true
    }

    // MARK: - Home / End

    package func focusFirstListItem() {
        state.cursor.focusFirst(in: visibleItems)
    }

    package func focusLastListItem() {
        state.cursor.focusLast(in: visibleItems)
    }

    // MARK: - Quick Look / open

    /// URL for Quick Look (F3) when a single file is selected.
    package func previewURLForQuickLook() -> URL? {
        guard let item = singleSelectedNonDirectoryItem() else { return nil }
        guard !item.isDirectory else { return nil }
        return item.url
    }

    /// Opens the selected file with the default application (F4).
    package func openSelectedFileWithDefaultApp() {
        guard let item = singleSelectedNonDirectoryItem() else { return }
        guard !item.isDirectory else { return }
        NSWorkspace.shared.open(item.url)
    }

    private func singleSelectedNonDirectoryItem() -> FileItem? {
        let ids = state.cursor.selected
        guard ids.count == 1, let id = ids.first else { return nil }
        return visibleItems.first(where: { $0.id == id && !$0.isParentDirectory })
    }

    // MARK: - Private

    private func clearDirectoryNavigationExtras() {
        resetTypeAheadBuffer()
        isPathBarEditing = false
    }

    /// Filters the full listing; keeps `..` when the filter is non-empty.
    package static func filteredItems(_ items: [FileItem], nameFilterText: String) -> [FileItem] {
        let trimmed = nameFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            if item.isParentDirectory { return true }
            return item.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Next row whose name starts with `buffer` (localized), searching after `focusedID`, wrapping.
    package static func typeAheadMatchID(items: [FileItem], focusedID: UUID?, buffer: String) -> UUID? {
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
