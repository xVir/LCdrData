import Testing
import Foundation
@testable import LCdrData

struct FileContextMenuModelTests {

    // MARK: - Fixtures

    private func file(_ name: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/dir/\(name)"), name: name, isDirectory: false)
    }

    private func directory(_ name: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/dir/\(name)"), name: name, isDirectory: true)
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
        let model = FileContextMenuModel.resolve(selection: [target.id], in: items)

        // Assert
        #expect(model.variant == .selection)
        #expect(model.items == [target])
        #expect(model.isSingleSelection)
        #expect(model.canRename)
        #expect(model.singleItem == target)
        #expect(model.urls == [target.url])
    }

    @Test func multipleRealItemsResolveToSelectionWithoutRenameAndPreserveOrder() {
        // Arrange
        let items = listing()
        let selection: Set<UUID> = [items[3].id, items[2].id] // b.txt, a.txt (reversed)

        // Act
        let model = FileContextMenuModel.resolve(selection: selection, in: items)

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
        let model = FileContextMenuModel.resolve(selection: [parent.id, real.id], in: items)

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
        let model = FileContextMenuModel.resolve(selection: [parent.id], in: items)

        // Assert
        #expect(model.variant == .parent)
        #expect(model.items.isEmpty)
        #expect(model.singleItem == nil)
        #expect(model.urls.isEmpty)
    }

    // MARK: - Background variant

    @Test func emptySelectionResolvesToBackgroundVariant() {
        // Arrange
        let items = listing()

        // Act
        let model = FileContextMenuModel.resolve(selection: [], in: items)

        // Assert
        #expect(model.variant == .background)
        #expect(model.items.isEmpty)
    }

    @Test func unknownIDsResolveToBackgroundVariant() {
        // Arrange
        let items = listing()

        // Act — a selection of IDs not present in the listing.
        let model = FileContextMenuModel.resolve(selection: [UUID()], in: items)

        // Assert
        #expect(model.variant == .background)
        #expect(model.items.isEmpty)
    }
}
