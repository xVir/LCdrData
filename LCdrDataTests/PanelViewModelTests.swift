import Testing
import Foundation
@testable import LCdrData

// MARK: - Mock File System Service

/// A mock FileSystemService that returns predefined items for testing.
nonisolated final class MockFileSystemService: FileSystemServiceProtocol, Sendable {
    let items: [FileItem]

    nonisolated init(items: [FileItem] = []) {
        self.items = items
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
        await vm.loadDirectory()

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
        await vm.loadDirectory()

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
        #expect(vm.state.selectedItemIDs.contains(item.id))

        // Act — deselect
        vm.toggleSelection(of: item.id)
        #expect(!vm.state.selectedItemIDs.contains(item.id))
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
        await vm.loadDirectory()

        // Act
        vm.selectAll()

        // Assert — parent entry should not be selected
        let parentItem = vm.state.items.first { $0.isParentDirectory }
        if let parentItem {
            #expect(!vm.state.selectedItemIDs.contains(parentItem.id))
        }
        #expect(vm.state.selectedItemIDs.count == 3)
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
        await vm.loadDirectory()
        vm.selectAll()

        // Act
        vm.deselectAll()

        // Assert
        #expect(vm.state.selectedItemIDs.isEmpty)
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
        #expect(vm.state.focusedItemID == itemID)
    }
}
