import Testing
import Foundation
@testable import Models

struct FileContextMenuModelTests {

    // MARK: - Fixtures

    private func file(_ name: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/dir/\(name)"), name: name, isDirectory: false)
    }

    private func directory(_ name: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/dir/\(name)"), name: name, isDirectory: true)
    }

    private func resolve(selection: Set<UUID>, in listing: [FileItem]) -> FileContextMenuModel {
        FileContextMenuModel.resolve(
            selection: selection,
            in: listing,
            currentDirectory: URL(fileURLWithPath: "/dir")
        )
    }

    private func listing() -> [FileItem] {
        [
            FileItem.parentEntry(for: URL(fileURLWithPath: "/dir")),
            directory("sub"),
            file("a.txt"),
            file("b.txt")
        ]
    }

    // MARK: - Selection variant

    @Test func singleRealItemResolvesToSelectionVariant() {
        // Arrange
        let items = listing()
        let target = items[2] // a.txt

        // Act
        let model = resolve(selection: [target.id], in: items)

        // Assert
        #expect(model.variant == .selection)
        #expect(model.items == [target])
        #expect(model.isSingleSelection)
        #expect(model.canRename)
        #expect(model.singleItem == target)
        #expect(model.urls == [target.url])
        #expect(model.terminalDirectory == nil)
    }

    @Test func multipleRealItemsResolveToSelectionWithoutRenameAndPreserveOrder() {
        // Arrange
        let items = listing()
        let selection: Set<UUID> = [items[3].id, items[2].id] // b.txt, a.txt (reversed)

        // Act
        let model = resolve(selection: selection, in: items)

        // Assert
        #expect(model.variant == .selection)
        #expect(!model.isSingleSelection)
        #expect(!model.canRename)
        #expect(model.singleItem == nil)
        // Order follows the listing, not the set.
        #expect(model.items == [items[2], items[3]])
    }

    @Test func parentRowMixedWithRealItemIsFilteredOutOfSelection() {
        // Arrange
        let items = listing()
        let parent = items[0]
        let real = items[2] // a.txt

        // Act
        let model = resolve(selection: [parent.id, real.id], in: items)

        // Assert
        #expect(model.variant == .selection)
        #expect(model.items == [real]) // parent excluded
        #expect(model.isSingleSelection)
    }

    // MARK: - Parent variant

    @Test func onlyParentRowResolvesToParentVariant() {
        // Arrange
        let items = listing()
        let parent = items[0]

        // Act
        let model = resolve(selection: [parent.id], in: items)

        // Assert
        #expect(model.variant == .parent)
        #expect(model.items.isEmpty)
        #expect(model.singleItem == nil)
        #expect(model.urls.isEmpty)
        #expect(model.terminalDirectory == URL(fileURLWithPath: "/dir"))
    }

    // MARK: - Background variant

    @Test func emptySelectionResolvesToBackgroundVariant() {
        // Arrange
        let items = listing()

        // Act
        let model = resolve(selection: [], in: items)

        // Assert
        #expect(model.variant == .background)
        #expect(model.items.isEmpty)
        #expect(model.terminalDirectory == nil)
    }

    @Test func unknownIDsResolveToBackgroundVariant() {
        // Arrange
        let items = listing()

        // Act — a selection of IDs not present in the listing.
        let model = resolve(selection: [UUID()], in: items)

        // Assert
        #expect(model.variant == .background)
        #expect(model.items.isEmpty)
        #expect(model.terminalDirectory == nil)
    }

    // MARK: - Open in Terminal

    @Test func singleFolderResolvesToThatFolder() {
        let items = listing()
        let folder = items[1]

        let model = resolve(selection: [folder.id], in: items)

        #expect(model.variant == .selection)
        #expect(model.terminalDirectory == folder.url)
    }

    @Test func twoFoldersDoNotResolveATerminalDirectory() {
        let first = directory("one")
        let second = directory("two")

        let model = resolve(selection: [first.id, second.id], in: [first, second])

        #expect(model.terminalDirectory == nil)
    }

    @Test func symlinkToDirectoryResolvesToThatPath() {
        let link = FileItem(
            url: URL(fileURLWithPath: "/dir/link"),
            name: "link",
            isDirectory: false,
            isSymlink: true,
            isSymlinkToDirectory: true
        )

        let model = resolve(selection: [link.id], in: [link])

        #expect(model.terminalDirectory == link.url)
    }

    @Test func archiveFolderDoesNotResolveATerminalDirectory() {
        let folder = FileItem(
            archiveContainer: URL(fileURLWithPath: "/tmp/files.zip"),
            internalPath: "reports",
            name: "reports",
            isDirectory: true
        )

        let model = resolve(selection: [folder.id], in: [folder])

        #expect(model.terminalDirectory == nil)
    }

    @Test func parentInsideAnArchiveDoesNotResolveATerminalDirectory() {
        let parent = FileItem(
            archiveContainer: URL(fileURLWithPath: "/tmp/files.zip"),
            internalPath: "reports",
            name: "..",
            isDirectory: true,
            isParentDirectory: true
        )

        let model = resolve(selection: [parent.id], in: [parent])

        #expect(model.variant == .parent)
        #expect(model.terminalDirectory == nil)
    }
}
