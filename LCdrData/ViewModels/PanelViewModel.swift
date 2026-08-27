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
    /// Whether mutating operations are allowed at the current location.
    package private(set) var isLocationWritable: Bool = true
    /// True when the last load failure was a sandbox permission denial.
    package var isPermissionError: Bool = false

    /// When set, the row with this ID plays a highlight animation (fading
    /// green background). Cleared automatically after the animation ends.
    package var highlightedItemID: UUID?

    /// When true, the path bar shows an editable path field (Cmd+L).
    package var isPathBarEditing: Bool = false

    /// Bundle ID of the application F4 opens files with (`editor.default-app`).
    /// Pushed in by `AppState` from the effective configuration; `nil` means
    /// fall back to the system default handler.
    package var editorDefaultAppBundleID: String?

    // MARK: - Type-ahead (incremental search)

    private var typeAheadBuffer: String = ""
    private var typeAheadLastEvent: Date = .distantPast
    private let typeAheadResetInterval: TimeInterval = 1.0

    // MARK: - Dependencies

    package let side: PanelSide
    private let fileSystemService: FileSystemServiceProtocol
    private let archiveService: ArchiveServiceProtocol
    private let fileOpeningService: FileOpeningServiceProtocol
    private let sandboxAccessService: SandboxAccessService
    private let directoryWatchingEnabled: Bool
    private var temporaryExtractionDirectories: [URL] = []

    // MARK: - Init

    package init(
        side: PanelSide,
        initialDirectory: URL,
        sortDescriptor: FileSortDescriptor? = nil,
        showHiddenFiles: Bool? = nil,
        editorDefaultAppBundleID: String? = nil,
        directoryWatchingEnabled: Bool = false,
        fileSystemService: FileSystemServiceProtocol = FileSystemService(),
        archiveService: ArchiveServiceProtocol = ArchiveService(),
        fileOpeningService: FileOpeningServiceProtocol = FileOpeningService(),
        sandboxAccessService: SandboxAccessService = SandboxAccessService(
            presenter: NoopAccessPresenter(),
            bookmarkStore: BookmarkStore()
        )
    ) {
        self.side = side
        self.editorDefaultAppBundleID = editorDefaultAppBundleID
        self.directoryWatchingEnabled = directoryWatchingEnabled
        self.state = PanelState(
            currentDirectory: initialDirectory,
            sortDescriptor: sortDescriptor ?? FileSortDescriptor(column: .name, ascending: true),
            showHiddenFiles: showHiddenFiles ?? false
        )
        self.fileSystemService = fileSystemService
        self.archiveService = archiveService
        self.fileOpeningService = fileOpeningService
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
            let items: [FileItem]
            switch state.location {
            case .directory(let url):
                isLocationWritable = true
                items = try await fileSystemService.listDirectory(
                    at: url,
                    showHidden: state.showHiddenFiles
                )
            case .zipArchive(let container, let internalPath):
                isLocationWritable = await archiveService.isWritable(container: container)
                items = try await archiveService.list(
                    container: container,
                    internalPath: internalPath,
                    showHidden: state.showHiddenFiles
                )
            }

            let sorted = sortItems(items)
            var displayItems: [FileItem] = []
            if !Self.sameLocation(state.location, .directory(URL(fileURLWithPath: "/"))) {
                displayItems.append(FileItem.parentEntry(for: state.location))
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
            if state.location.isArchive {
                isLocationWritable = false
            }
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
        let url = state.location.watchURL
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
        await navigate(to: .directory(url))
    }

    package func navigate(to location: BrowseLocation) async {
        clearDirectoryNavigationExtras()

        let currentLocation = state.location
        let intent: Cursor.Intent
        if Self.sameLocation(location, currentLocation.parent) {
            switch currentLocation {
            case .directory(let url):
                intent = .landOnChild(url)
            case .zipArchive(let container, let internalPath) where internalPath.isEmpty:
                intent = .landOnChild(container)
            case .zipArchive:
                intent = .fresh
            }
        } else {
            intent = .fresh
        }

        await performAtomicNavigation(intent: intent, displayURL: location.watchURL) {
            // Truncate forward history if we navigated back previously
            if self.state.historyIndex < self.state.locationHistory.count - 1 {
                self.state.locationHistory = Array(
                    self.state.locationHistory.prefix(self.state.historyIndex + 1)
                )
            }
            self.state.location = location
            self.state.locationHistory.append(location)
            self.state.historyIndex = self.state.locationHistory.count - 1
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
            location: state.location,
            history: state.locationHistory,
            historyIndex: state.historyIndex,
            cursor: state.cursor
        )

        mutate()
        await reload(intent)

        guard errorMessage != nil else { return }

        if isPermissionError {
            let granted = await sandboxAccessService.requestAccessIfNeeded(
                context: .reactive(
                    displayURL: displayURL,
                    resolvedTarget: displayURL.resolvingSymlinksInPath()
                )
            )
            if granted != nil {
                await reload(intent)
            }
        }

        if errorMessage != nil {
            let navigationError = errorMessage
            let navigationWasPermissionError = isPermissionError
            state.location = snapshot.location
            state.locationHistory = snapshot.history
            state.historyIndex = snapshot.historyIndex
            state.cursor = snapshot.cursor
            await reload(.keepSelection)
            errorMessage = navigationError
            isPermissionError = navigationWasPermissionError
        }
    }

    private struct NavigationSnapshot {
        let location: BrowseLocation
        let history: [BrowseLocation]
        let historyIndex: Int
        let cursor: Cursor
    }

    /// Navigate to the parent directory.
    /// After loading the parent listing, the cursor will land on the folder
    /// we just left so the user can easily re-enter it.
    package func navigateToParent() async {
        let parent = state.location.parent
        guard parent != state.location else { return }
        await navigate(to: parent)
    }

    /// Navigate back in history. On permission denial of the back-target,
    /// the navigation reverts atomically.
    package func navigateBack() async {
        guard state.historyIndex > 0 else { return }
        clearDirectoryNavigationExtras()
        let target = state.locationHistory[state.historyIndex - 1]
        await performAtomicNavigation(intent: .fresh, displayURL: target.watchURL) {
            self.state.historyIndex -= 1
            self.state.location = target
        }
    }

    /// Navigate forward in history. On permission denial of the forward-target,
    /// the navigation reverts atomically.
    package func navigateForward() async {
        guard state.historyIndex < state.locationHistory.count - 1 else { return }
        clearDirectoryNavigationExtras()
        let target = state.locationHistory[state.historyIndex + 1]
        await performAtomicNavigation(intent: .fresh, displayURL: target.watchURL) {
            self.state.historyIndex += 1
            self.state.location = target
        }
    }

    /// Opens a row: parent → up, directory → enter, file → default app.
    package func openItem(_ item: FileItem) async {
        if item.isParentDirectory {
            await navigateToParent()
            return
        }
        if item.isArchive {
            await navigate(to: .zipArchive(container: item.url, internalPath: ""))
        } else if item.isNavigableDirectory {
            if let container = item.archiveContainer, let internalPath = item.archiveInternalPath {
                await navigate(to: .zipArchive(container: container, internalPath: internalPath))
            } else {
                await navigate(to: item.url)
            }
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

    /// Prepares a selected archive member on disk for Quick Look or opening.
    package func preparedSelectedFileURL() async -> URL? {
        guard let item = singleSelectedNonDirectoryItem(), !item.isDirectory else { return nil }
        return await preparedFileURL(for: item)
    }

    package func preparedFileURL(for item: FileItem) async -> URL? {
        guard
            let container = item.archiveContainer,
            let internalPath = item.archiveInternalPath
        else {
            return item.url
        }

        do {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LCdrData-Preview-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try await archiveService.extract(
                container: container,
                paths: [internalPath],
                to: temporaryDirectory
            )
            temporaryExtractionDirectories.append(temporaryDirectory)
            return temporaryDirectory.appendingPathComponent(item.name)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Opens the selected file (F4) with the configured editor, falling back
    /// to the system default handler when none is configured or installed.
    package func openPreparedSelectedFileWithDefaultApp() async {
        guard let url = await preparedSelectedFileURL() else { return }
        await fileOpeningService.open(url, preferredApplicationBundleID: editorDefaultAppBundleID)
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

    private static func sameLocation(_ lhs: BrowseLocation, _ rhs: BrowseLocation) -> Bool {
        switch (lhs, rhs) {
        case (.directory(let left), .directory(let right)):
            return left.standardizedFileURL.path == right.standardizedFileURL.path
        case (
            .zipArchive(let leftContainer, let leftPath),
            .zipArchive(let rightContainer, let rightPath)
        ):
            return leftContainer.standardizedFileURL.path == rightContainer.standardizedFileURL.path
                && leftPath == rightPath
        default:
            return false
        }
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
