import Foundation
import Testing
@testable import LCdrData

@MainActor
struct PanelViewModelPhase3Tests {

    private func sampleItems() -> [FileItem] {
        let parent = FileItem.parentEntry(for: URL(fileURLWithPath: "/tmp"))
        let a = FileItem(
            url: URL(fileURLWithPath: "/tmp/alpha"),
            name: "alpha",
            isDirectory: true
        )
        let b = FileItem(
            url: URL(fileURLWithPath: "/tmp/apple.txt"),
            name: "apple.txt",
            isDirectory: false
        )
        let c = FileItem(
            url: URL(fileURLWithPath: "/tmp/beta.txt"),
            name: "beta.txt",
            isDirectory: false
        )
        return [parent, a, b, c]
    }

    @Test func filteredItemsKeepsParentWhenFilterNonEmpty() {
        let items = sampleItems()
        // "apple" matches only apple.txt; parent row is always kept.
        let filtered = PanelViewModel.filteredItems(items, nameFilterText: "apple")
        #expect(filtered.count == 2)
        #expect(filtered.contains(where: { $0.isParentDirectory }))
        #expect(filtered.contains(where: { $0.name == "apple.txt" }))
    }

    @Test func filteredItemsEmptyFilterReturnsAll() {
        let items = sampleItems()
        let filtered = PanelViewModel.filteredItems(items, nameFilterText: "")
        #expect(filtered.count == items.count)
    }

    @Test func typeAheadMatchFindsNextAfterFocus() {
        let items = sampleItems()
        let parentID = items[0].id
        let alphaID = items[1].id
        let appleID = items[2].id

        let first = PanelViewModel.typeAheadMatchID(items: items, focusedID: parentID, buffer: "a")
        #expect(first == alphaID)

        let second = PanelViewModel.typeAheadMatchID(items: items, focusedID: alphaID, buffer: "a")
        #expect(second == appleID)

        let wrap = PanelViewModel.typeAheadMatchID(items: items, focusedID: appleID, buffer: "a")
        #expect(wrap == alphaID)
    }

    @Test func typeAheadMatchRespectsBuffer() {
        let items = sampleItems()
        let betaID = items[3].id
        let match = PanelViewModel.typeAheadMatchID(items: items, focusedID: nil, buffer: "bet")
        #expect(match == betaID)
    }

    @Test func visibleItemsMatchesStateItems() {
        let vm = PanelViewModel(side: .left, initialDirectory: URL(fileURLWithPath: "/tmp"))
        let items = sampleItems()
        vm.state.items = items
        #expect(vm.visibleItems.map(\.id) == items.map(\.id))
    }
}
