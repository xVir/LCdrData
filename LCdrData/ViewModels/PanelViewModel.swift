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

    /// Navigates into a directory, pushing to history.
    func navigate(to url: URL) async {
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
        state.historyIndex -= 1
        state.currentDirectory = state.history[state.historyIndex]
        await loadDirectory()
    }

    /// Navigate forward in history.
    func navigateForward() async {
        guard state.historyIndex < state.history.count - 1 else { return }
        state.historyIndex += 1
        state.currentDirectory = state.history[state.historyIndex]
        await loadDirectory()
    }

    /// Opens the currently selected item — if it's a directory, navigate into it.
    /// Uses the List selection (single selected item) rather than `focusedItemID`,
    /// because arrow-key navigation in the List updates `selectedItemIDs`.
    func openSelectedItem() async {
        // Use selection if exactly one item is selected; fall back to focusedItemID.
        let targetID: UUID? = if state.selectedItemIDs.count == 1 {
            state.selectedItemIDs.first
        } else {
            state.focusedItemID
        }

        guard let targetID,
              let item = state.items.first(where: { $0.id == targetID }) else {
            return
        }

        if item.isDirectory {
            await navigate(to: item.url)
        }
        // For files, Phase 1 only supports directory navigation.
        // File opening (Quick Look, editor) is Phase 2+.
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

    /// Selects all items (excluding ".." parent entry).
    func selectAll() {
        state.selectedItemIDs = Set(
            state.items
                .filter { !$0.isParentDirectory }
                .map(\.id)
        )
    }

    /// Deselects all items.
    func deselectAll() {
        state.selectedItemIDs = []
    }

    // MARK: - Hidden Files

    /// Toggles visibility of hidden files and reloads.
    func toggleHiddenFiles() async {
        state.showHiddenFiles.toggle()
        await loadDirectory()
    }
}
