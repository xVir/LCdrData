import Testing
import Foundation
@testable import Models
@testable import Services
@testable import ViewModels
@testable import TestSupport

// MARK: - Mock File System Service

/// A mock FileSystemService that returns predefined items for testing.
nonisolated final class MockFileSystemService: FileSystemServiceProtocol, Sendable {
    let items: [FileItem]
    private let itemsByPath: [String: [FileItem]]

    nonisolated init(items: [FileItem] = []) {
        self.items = items
        self.itemsByPath = [:]
    }

    /// Creates a mock that returns different items depending on the directory URL.
    nonisolated init(itemsByPath: [String: [FileItem]]) {
        self.items = []
        self.itemsByPath = itemsByPath
    }

    func listDirectory(at url: URL, showHidden: Bool) async throws -> [FileItem] {
        if !itemsByPath.isEmpty {
            return itemsByPath[url.path] ?? []
        }
        return items
    }
}

/// A mock that lists items for some paths and throws a configured error for
/// others — used to exercise permission-error handling in `navigate(to:)`.
nonisolated final class ThrowingMockFileSystemService: FileSystemServiceProtocol, Sendable {
    let itemsByPath: [String: [FileItem]]
    let failingPaths: Set<String>
    let error: NSError

    nonisolated init(
        itemsByPath: [String: [FileItem]] = [:],
        failingPaths: Set<String>,
        error: NSError
    ) {
        self.itemsByPath = itemsByPath
        self.failingPaths = failingPaths
        self.error = error
    }

    func listDirectory(at url: URL, showHidden: Bool) async throws -> [FileItem] {
        if failingPaths.contains(url.path) {
            throw error
        }
        return itemsByPath[url.path] ?? []
    }
}

/// A mutable mock whose items can be changed between calls to simulate
/// external file system changes (e.g. files created while the app was
/// in the background).
nonisolated final class MutableMockFileSystemService: FileSystemServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [FileItem]

    nonisolated init(items: [FileItem] = []) {
        self._items = items
    }

    var items: [FileItem] {
        get { lock.withLock { _items } }
        set { lock.withLock { _items = newValue } }
    }

    func listDirectory(at url: URL, showHidden: Bool) async throws -> [FileItem] {
        return items
    }
}

// MARK: - Tests

@MainActor
struct PanelViewModelTests {

    private func makeTestItems() -> [FileItem] {
        [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/alpha"),
                name: "alpha",
                isDirectory: true,
                size: nil,
                modificationDate: Date(timeIntervalSince1970: 1000)
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/beta.txt"),
                name: "beta.txt",
                isDirectory: false,
                size: 500,
                modificationDate: Date(timeIntervalSince1970: 2000)
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/gamma.pdf"),
                name: "gamma.pdf",
                isDirectory: false,
                size: 3000,
                modificationDate: Date(timeIntervalSince1970: 500)
            ),
        ]
    }

    @Test func loadDirectoryPopulatesItems() async {
        // Arrange
        let items = makeTestItems()
        let service = MockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )

        // Act
        await vm.reload(.fresh)

        // Assert — should have ".." plus the 3 items
        #expect(vm.state.items.count == 4)
        #expect(vm.state.items.first?.isParentDirectory == true)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadDirectoryAtRootHasNoParentEntry() async {
        // Arrange
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/"),
            fileSystemService: service
        )

        // Act
        await vm.reload(.fresh)

        // Assert — root should not have ".." entry
        #expect(vm.state.items.isEmpty)
    }

    @Test func navigatePushesToHistory() async {
        // Arrange
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )

        // Act
        await vm.navigate(to: URL(fileURLWithPath: "/tmp/subdir"))

        // Assert
        #expect(vm.state.currentDirectory == URL(fileURLWithPath: "/tmp/subdir"))
        #expect(vm.state.history.count == 2)
        #expect(vm.state.historyIndex == 1)
    }

    @Test func navigateBackAndForward() async {
        // Arrange
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/a"),
            fileSystemService: service
        )
        await vm.navigate(to: URL(fileURLWithPath: "/b"))
        await vm.navigate(to: URL(fileURLWithPath: "/c"))

        // Act — go back
        await vm.navigateBack()

        // Assert
        #expect(vm.state.currentDirectory == URL(fileURLWithPath: "/b"))
        #expect(vm.state.historyIndex == 1)

        // Act — go forward
        await vm.navigateForward()

        // Assert
        #expect(vm.state.currentDirectory == URL(fileURLWithPath: "/c"))
        #expect(vm.state.historyIndex == 2)
    }

    @Test func navigateBackAtStartDoesNothing() async {
        // Arrange
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )

        // Act
        await vm.navigateBack()

        // Assert
        #expect(vm.state.currentDirectory == URL(fileURLWithPath: "/tmp"))
        #expect(vm.state.historyIndex == 0)
    }

    @Test func sortItemsDirectoriesFirst() {
        // Arrange
        let items = [
            FileItem(url: URL(fileURLWithPath: "/z.txt"), name: "z.txt", isDirectory: false),
            FileItem(url: URL(fileURLWithPath: "/a_dir"), name: "a_dir", isDirectory: true),
            FileItem(url: URL(fileURLWithPath: "/b.txt"), name: "b.txt", isDirectory: false),
        ]
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/"),
            fileSystemService: service
        )

        // Act
        let sorted = vm.sortItems(items)

        // Assert — directories first, then files, both alphabetical
        #expect(sorted[0].name == "a_dir")
        #expect(sorted[0].isDirectory == true)
        #expect(sorted[1].name == "b.txt")
        #expect(sorted[2].name == "z.txt")
    }

    @Test func selectionToggle() {
        // Arrange
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/file"),
            name: "file",
            isDirectory: false
        )
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )

        // Act — select
        vm.toggleSelection(of: item.id)
        #expect(vm.state.cursor.selected.contains(item.id))

        // Act — deselect
        vm.toggleSelection(of: item.id)
        #expect(!vm.state.cursor.selected.contains(item.id))
    }

    @Test func selectAllExcludesParentEntry() async {
        // Arrange
        let items = makeTestItems()
        let service = MockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)

        // Act
        vm.selectAll()

        // Assert — parent entry should not be selected
        let parentItem = vm.state.items.first { $0.isParentDirectory }
        if let parentItem {
            #expect(!vm.state.cursor.selected.contains(parentItem.id))
        }
        #expect(vm.state.cursor.selected.count == 3)
    }

    @Test func deselectAll() async {
        // Arrange
        let items = makeTestItems()
        let service = MockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)
        vm.selectAll()

        // Act
        vm.deselectAll()

        // Assert
        #expect(vm.state.cursor.selected.isEmpty)
    }

    @Test func emptySelectionFromEmptySpaceClickPublishesEmptyThenRestoresFocusedRow() async {
        // Arrange — cursor sitting on the first real row, as after a row click.
        let items = makeTestItems()
        let service = MockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)
        let focusedID = vm.state.items[1].id
        vm.cursorDidChangeSelection(to: [focusedID])

        // Act — the list clears itself and hands back an empty set.
        vm.cursorDidChangeSelection(to: [])

        // Assert — momentarily empty so the list observes a real change...
        #expect(vm.state.cursor.selected.isEmpty)
        #expect(vm.state.cursor.focused == focusedID)

        // ...and restored a runloop turn later.
        await Task.yield()
        #expect(vm.state.cursor.selected == [focusedID])
        #expect(vm.state.cursor.focused == focusedID)
    }

    @Test func emptySelectionResyncDoesNotOverwriteASelectionMadeInTheMeantime() async {
        // Arrange
        let items = makeTestItems()
        let service = MockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)
        let firstID = vm.state.items[1].id
        let secondID = vm.state.items[2].id
        vm.cursorDidChangeSelection(to: [firstID])

        // Act — an empty-space click immediately followed by a click on another row.
        vm.cursorDidChangeSelection(to: [])
        vm.cursorDidChangeSelection(to: [secondID])
        await Task.yield()

        // Assert — the pending restore must not resurrect the stale row.
        #expect(vm.state.cursor.selected == [secondID])
        #expect(vm.state.cursor.focused == secondID)
    }

    @Test func emptySelectionWithNoFocusedRowLeavesSelectionEmpty() async {
        // Arrange
        let items = makeTestItems()
        let service = MockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)
        vm.state.cursor = Cursor()

        // Act
        vm.cursorDidChangeSelection(to: [])
        await Task.yield()

        // Assert — nothing to restore, so no resync is scheduled.
        #expect(vm.state.cursor.selected.isEmpty)
        #expect(vm.state.cursor.focused == nil)
    }

    @Test func toggleHiddenFiles() async {
        // Arrange
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        #expect(vm.state.showHiddenFiles == false)

        // Act
        await vm.toggleHiddenFiles()

        // Assert
        #expect(vm.state.showHiddenFiles == true)
    }

    @Test func setFocused() {
        // Arrange
        let service = MockFileSystemService(items: [])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        let itemID = UUID()

        // Act
        vm.setFocused(itemID)

        // Assert
        #expect(vm.state.cursor.focused == itemID)
    }

    // MARK: - Navigate to Parent Focuses Child Folder

    @Test func navigateToParentFocusesChildFolder() async {
        // Arrange — parent directory contains the child folder "subdir" and a file
        let parentItems = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/subdir"),
                name: "subdir",
                isDirectory: true
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/other"),
                name: "other",
                isDirectory: true
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/file.txt"),
                name: "file.txt",
                isDirectory: false,
                size: 100
            ),
        ]
        let service = MockFileSystemService(itemsByPath: [
            "/tmp": parentItems,
            "/tmp/subdir": [],
        ])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp/subdir"),
            fileSystemService: service
        )

        // Act — navigate to parent
        await vm.navigateToParent()

        // Assert — focused and selected item should be "subdir", not the first item
        let subdirItem = vm.state.items.first { $0.name == "subdir" }
        #expect(subdirItem != nil)
        #expect(vm.state.cursor.focused == subdirItem?.id)
        #expect(vm.state.cursor.selected == [subdirItem!.id])
    }

    @Test func navigateToParentViaNavigateFocusesChildFolder() async {
        // Arrange — simulates navigating to parent via ".." entry or breadcrumb
        let parentItems = [
            FileItem(
                url: URL(fileURLWithPath: "/home/docs"),
                name: "docs",
                isDirectory: true
            ),
            FileItem(
                url: URL(fileURLWithPath: "/home/music"),
                name: "music",
                isDirectory: true
            ),
        ]
        let service = MockFileSystemService(itemsByPath: [
            "/home": parentItems,
            "/home/docs": [],
        ])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/home/docs"),
            fileSystemService: service
        )

        // Act — navigate directly to parent URL (as ".." entry or breadcrumb would)
        await vm.navigate(to: URL(fileURLWithPath: "/home"))

        // Assert — focused item should be "docs"
        let docsItem = vm.state.items.first { $0.name == "docs" }
        #expect(docsItem != nil)
        #expect(vm.state.cursor.focused == docsItem?.id)
        #expect(vm.state.cursor.selected == [docsItem!.id])
    }

    @Test func navigateToNonParentDoesNotFocusChild() async {
        // Arrange — navigating to a sibling directory should NOT trigger child focus
        let siblingItems = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/sibling/file.txt"),
                name: "file.txt",
                isDirectory: false,
                size: 42
            ),
        ]
        let service = MockFileSystemService(itemsByPath: [
            "/tmp/subdir": [],
            "/tmp/sibling": siblingItems,
        ])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp/subdir"),
            fileSystemService: service
        )

        // Act — navigate to a sibling, not to the parent
        await vm.navigate(to: URL(fileURLWithPath: "/tmp/sibling"))

        // Assert — should focus the first item (default behavior), which is ".."
        let firstItem = vm.state.items.first
        #expect(firstItem != nil)
        #expect(vm.state.cursor.focused == firstItem?.id)
    }

    @Test func navigateToParentWhenChildNotFoundFallsBackToFirst() async {
        // Arrange — parent listing does not contain the child folder
        // (e.g., it was deleted while we were inside it)
        let parentItems = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/other"),
                name: "other",
                isDirectory: true
            ),
        ]
        let service = MockFileSystemService(itemsByPath: [
            "/tmp": parentItems,
            "/tmp/gone": [],
        ])
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp/gone"),
            fileSystemService: service
        )

        // Act
        await vm.navigateToParent()

        // Assert — should fall back to the first item (".." entry)
        let firstItem = vm.state.items.first
        #expect(firstItem != nil)
        #expect(firstItem?.isParentDirectory == true)
        #expect(vm.state.cursor.focused == firstItem?.id)
    }

    // MARK: - Reload Keeping Selection

    @Test func reloadKeepingSelectionPreservesSelectedItem() async {
        // Arrange — load directory, then select a specific file
        let initialItems = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/alpha"),
                name: "alpha",
                isDirectory: true
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/beta.txt"),
                name: "beta.txt",
                isDirectory: false,
                size: 100
            ),
        ]
        let service = MutableMockFileSystemService(items: initialItems)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)

        // Select beta.txt
        let betaItem = vm.state.items.first { $0.name == "beta.txt" }!
        vm.state.cursor.selected = [betaItem.id]
        vm.state.cursor.focused = betaItem.id

        // Simulate external change: a new file appears
        service.items = initialItems + [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/new_file.txt"),
                name: "new_file.txt",
                isDirectory: false,
                size: 200
            ),
        ]

        // Act — reload keeping selection
        await vm.reload(.keepSelection)

        // Assert — beta.txt should still be selected and focused
        // (IDs are deterministic from URL, so the same file keeps the same ID)
        let newBeta = vm.state.items.first { $0.name == "beta.txt" }
        #expect(newBeta != nil)
        #expect(vm.state.cursor.selected == [newBeta!.id])
        #expect(vm.state.cursor.focused == newBeta!.id)
        // New file should be in the list
        #expect(vm.state.items.contains { $0.name == "new_file.txt" })
    }

    @Test func reloadKeepingSelectionPreservesMultipleSelections() async {
        // Arrange
        let items = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/a.txt"),
                name: "a.txt",
                isDirectory: false,
                size: 10
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/b.txt"),
                name: "b.txt",
                isDirectory: false,
                size: 20
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/c.txt"),
                name: "c.txt",
                isDirectory: false,
                size: 30
            ),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)

        // Select a.txt and c.txt, focus on c.txt
        let aItem = vm.state.items.first { $0.name == "a.txt" }!
        let cItem = vm.state.items.first { $0.name == "c.txt" }!
        vm.state.cursor.selected = [aItem.id, cItem.id]
        vm.state.cursor.focused = cItem.id

        // Act
        await vm.reload(.keepSelection)

        // Assert — both items restored, focus on c.txt
        let newA = vm.state.items.first { $0.name == "a.txt" }!
        let newC = vm.state.items.first { $0.name == "c.txt" }!
        #expect(vm.state.cursor.selected == [newA.id, newC.id])
        #expect(vm.state.cursor.focused == newC.id)
    }

    @Test func reloadKeepingSelectionFallsBackToSamePositionWhenLastItemDeleted() async {
        // Arrange — select the last file, then it gets deleted.
        // Cursor should move to the new last item.
        let items = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/keep.txt"),
                name: "keep.txt",
                isDirectory: false,
                size: 10
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/gone.txt"),
                name: "gone.txt",
                isDirectory: false,
                size: 20
            ),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)
        // Items after load: ["..", "keep.txt", "gone.txt"]  (sorted by name)

        // Select gone.txt (last item, index 2)
        let goneItem = vm.state.items.first { $0.name == "gone.txt" }!
        vm.state.cursor.selected = [goneItem.id]
        vm.state.cursor.focused = goneItem.id

        // Simulate deletion
        service.items = [items[0]]

        // Act
        await vm.reload(.keepSelection)

        // Assert — cursor clamps to new last item: "keep.txt"
        let keepItem = vm.state.items.first { $0.name == "keep.txt" }
        #expect(keepItem != nil)
        #expect(vm.state.cursor.focused == keepItem?.id)
        #expect(vm.state.cursor.selected == [keepItem!.id])
    }

    @Test func reloadKeepingSelectionFallsBackToSamePositionWhenMiddleItemDeleted() async {
        // Arrange — select a middle file, then it gets deleted.
        // Cursor should stay at the same index (the next file slides in).
        let items = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/a.txt"),
                name: "a.txt",
                isDirectory: false,
                size: 10
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/b.txt"),
                name: "b.txt",
                isDirectory: false,
                size: 20
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/c.txt"),
                name: "c.txt",
                isDirectory: false,
                size: 30
            ),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)
        // Items after load: ["..", "a.txt", "b.txt", "c.txt"]

        // Select b.txt (index 2)
        let bItem = vm.state.items.first { $0.name == "b.txt" }!
        vm.state.cursor.selected = [bItem.id]
        vm.state.cursor.focused = bItem.id

        // Simulate deletion of b.txt
        service.items = [items[0], items[2]]

        // Act
        await vm.reload(.keepSelection)
        // Items after reload: ["..", "a.txt", "c.txt"]

        // Assert — cursor stays at index 2, which is now "c.txt"
        let cItem = vm.state.items.first { $0.name == "c.txt" }
        #expect(cItem != nil)
        #expect(vm.state.cursor.focused == cItem?.id)
        #expect(vm.state.cursor.selected == [cItem!.id])
    }

    @Test func reloadKeepingSelectionFallsBackToSamePositionWhenFirstNonParentItemDeleted() async {
        // Arrange — select the first real file (right after ".."), then delete it.
        // Cursor should stay at the same index (the next file slides in).
        let items = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/a.txt"),
                name: "a.txt",
                isDirectory: false,
                size: 10
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/b.txt"),
                name: "b.txt",
                isDirectory: false,
                size: 20
            ),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)
        // Items after load: ["..", "a.txt", "b.txt"]

        // Select a.txt (index 1)
        let aItem = vm.state.items.first { $0.name == "a.txt" }!
        vm.state.cursor.selected = [aItem.id]
        vm.state.cursor.focused = aItem.id

        // Simulate deletion of a.txt
        service.items = [items[1]]

        // Act
        await vm.reload(.keepSelection)
        // Items after reload: ["..", "b.txt"]

        // Assert — cursor stays at index 1, which is now "b.txt"
        let bItem = vm.state.items.first { $0.name == "b.txt" }
        #expect(bItem != nil)
        #expect(vm.state.cursor.focused == bItem?.id)
        #expect(vm.state.cursor.selected == [bItem!.id])
    }

    // MARK: - prepareForDeletion + reload

    @Test func prepareForDeletionThenReloadFocusesNextItem() async {
        // Arrange: ["..", "a.txt", "b.txt", "c.txt"]  — delete b.txt
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false, size: 10),
            FileItem(url: URL(fileURLWithPath: "/tmp/b.txt"), name: "b.txt", isDirectory: false, size: 20),
            FileItem(url: URL(fileURLWithPath: "/tmp/c.txt"), name: "c.txt", isDirectory: false, size: 30),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)

        // Select b.txt
        let bItem = vm.state.items.first { $0.name == "b.txt" }!
        vm.state.cursor.selected = [bItem.id]
        vm.state.cursor.focused = bItem.id

        // Act — simulate delete then reload with the neighbour intent
        let bURL = bItem.url
        service.items = [items[0], items[2]]
        await vm.reload(.landOnNeighbourOf([bURL]))

        // Assert — focus moved to c.txt (next item after b.txt)
        let cItem = vm.state.items.first { $0.name == "c.txt" }!
        #expect(vm.state.cursor.focused == cItem.id)
        #expect(vm.state.cursor.selected == [cItem.id])
    }

    @Test func prepareForDeletionLastItemThenReloadFocusesPreviousItem() async {
        // Arrange: ["..", "a.txt", "b.txt"]  — delete b.txt (last)
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false, size: 10),
            FileItem(url: URL(fileURLWithPath: "/tmp/b.txt"), name: "b.txt", isDirectory: false, size: 20),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)

        // Select b.txt (last item)
        let bItem = vm.state.items.first { $0.name == "b.txt" }!
        vm.state.cursor.selected = [bItem.id]
        vm.state.cursor.focused = bItem.id

        // Act
        let bURL = bItem.url
        service.items = [items[0]]
        await vm.reload(.landOnNeighbourOf([bURL]))

        // Assert — focus moved to a.txt (previous item)
        let aItem = vm.state.items.first { $0.name == "a.txt" }!
        #expect(vm.state.cursor.focused == aItem.id)
        #expect(vm.state.cursor.selected == [aItem.id])
    }

    @Test func prepareForDeletionMultipleItemsThenReloadFocusesNextAfterLast() async {
        // Arrange: ["..", "a.txt", "b.txt", "c.txt", "d.txt"] — delete b.txt and c.txt
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false, size: 10),
            FileItem(url: URL(fileURLWithPath: "/tmp/b.txt"), name: "b.txt", isDirectory: false, size: 20),
            FileItem(url: URL(fileURLWithPath: "/tmp/c.txt"), name: "c.txt", isDirectory: false, size: 30),
            FileItem(url: URL(fileURLWithPath: "/tmp/d.txt"), name: "d.txt", isDirectory: false, size: 40),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)

        // Select b.txt and c.txt
        let bItem = vm.state.items.first { $0.name == "b.txt" }!
        let cItem = vm.state.items.first { $0.name == "c.txt" }!
        vm.state.cursor.selected = [bItem.id, cItem.id]
        vm.state.cursor.focused = cItem.id

        // Act
        let bURL = bItem.url
        let cURL = cItem.url
        service.items = [items[0], items[3]]
        await vm.reload(.landOnNeighbourOf([bURL, cURL]))

        // Assert — focus moved to d.txt (next item after the last selected)
        let dItem = vm.state.items.first { $0.name == "d.txt" }!
        #expect(vm.state.cursor.focused == dItem.id)
        #expect(vm.state.cursor.selected == [dItem.id])
    }

    @Test func prepareForDeletionFirstItemThenReloadFocusesNextItem() async {
        // Arrange: ["..", "a.txt", "b.txt"]  — delete a.txt (first real item)
        let items = [
            FileItem(url: URL(fileURLWithPath: "/tmp/a.txt"), name: "a.txt", isDirectory: false, size: 10),
            FileItem(url: URL(fileURLWithPath: "/tmp/b.txt"), name: "b.txt", isDirectory: false, size: 20),
        ]
        let service = MutableMockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: service
        )
        await vm.reload(.fresh)

        // Select a.txt
        let aItem = vm.state.items.first { $0.name == "a.txt" }!
        vm.state.cursor.selected = [aItem.id]
        vm.state.cursor.focused = aItem.id

        // Act
        let aURL = aItem.url
        service.items = [items[1]]
        await vm.reload(.landOnNeighbourOf([aURL]))

        // Assert — focus moved to b.txt (next item)
        let bItem = vm.state.items.first { $0.name == "b.txt" }!
        #expect(vm.state.cursor.focused == bItem.id)
        #expect(vm.state.cursor.selected == [bItem.id])
    }

    @Test func initialReloadPermissionErrorDoesNotInvokeReactivePrompt() async {
        // Arrange — initial directory throws permission error.
        let service = ThrowingMockFileSystemService(
            itemsByPath: [:],
            failingPaths: ["/a"],
            error: NSError(domain: NSCocoaErrorDomain, code: 257)
        )
        let presenter = FakeAccessPresenter(result: nil)
        let sandbox = SandboxAccessService(presenter: presenter, bookmarkStore: FakeBookmarkStore())
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/a"),
            fileSystemService: service,
            sandboxAccessService: sandbox
        )

        // Act — direct reload (the initial-load code path), NOT a user navigation.
        await vm.reload(.fresh)

        // Assert — the reactive prompt was never invoked; isPermissionError is set
        // so PanelView can render the empty-state hint, but the user isn't prompted.
        #expect(presenter.presentedContexts.isEmpty)
        #expect(vm.isPermissionError == true)
    }

    @Test func navigatePermissionErrorInvokesReactivePromptWithDisplayURL() async {
        // Arrange
        let service = ThrowingMockFileSystemService(
            itemsByPath: ["/a": []],
            failingPaths: ["/b"],
            error: NSError(domain: NSCocoaErrorDomain, code: 257)
        )
        let presenter = FakeAccessPresenter(result: nil)
        let sandbox = SandboxAccessService(presenter: presenter, bookmarkStore: FakeBookmarkStore())
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/a"),
            fileSystemService: service,
            sandboxAccessService: sandbox
        )
        await vm.reload(.fresh)

        // Act — user navigation to denied path.
        await vm.navigate(to: URL(fileURLWithPath: "/b"))

        // Assert — exactly one .reactive prompt, with the clicked URL as displayURL.
        #expect(presenter.presentedContexts.count == 1)
        if case .reactive(let displayURL, _) = presenter.presentedContexts.first {
            #expect(displayURL.path == "/b")
        } else {
            Issue.record("Expected a .reactive presentation context")
        }
    }

    @Test func navigateBackPermissionErrorRevertsHistoryIndex() async {
        // Arrange — panel at /b, with /a as the previous history entry,
        // but /a now denies access.
        let service = ThrowingMockFileSystemService(
            itemsByPath: ["/b": []],
            failingPaths: ["/a"],
            error: NSError(domain: NSCocoaErrorDomain, code: 257)
        )
        let sandbox = SandboxAccessService(
            presenter: NoopAccessPresenter(),
            bookmarkStore: FakeBookmarkStore()
        )
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/b"),
            fileSystemService: service,
            sandboxAccessService: sandbox
        )
        vm.state.history = [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]
        vm.state.historyIndex = 1
        await vm.reload(.fresh)
        #expect(vm.state.currentDirectory.path == "/b")

        // Act — back to /a; denied; user cancels.
        await vm.navigateBack()

        // Assert — panel stays at /b, historyIndex stays at 1.
        #expect(vm.state.currentDirectory.path == "/b")
        #expect(vm.state.historyIndex == 1)
    }

    @Test func navigatePermissionErrorWhenAccessDeniedRevertsCurrentDirectory() async {
        // Arrange — start at /a (success), navigation to /b throws permission error.
        let service = ThrowingMockFileSystemService(
            itemsByPath: ["/a": []],
            failingPaths: ["/b"],
            error: NSError(domain: NSCocoaErrorDomain, code: 257)
        )
        let sandbox = SandboxAccessService(
            presenter: NoopAccessPresenter(),  // user cancels
            bookmarkStore: FakeBookmarkStore()
        )
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/a"),
            fileSystemService: service,
            sandboxAccessService: sandbox
        )
        await vm.reload(.fresh)
        #expect(vm.state.currentDirectory.path == "/a")

        // Act — user navigates to /b, which is denied; presenter cancels.
        await vm.navigate(to: URL(fileURLWithPath: "/b"))

        // Assert — panel atomically reverts to /a.
        #expect(vm.state.currentDirectory.path == "/a")
    }
}
