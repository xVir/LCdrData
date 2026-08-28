import Testing
import Foundation
@testable import Models
@testable import Services
@testable import ViewModels

/// Records what reached storage, without touching `UserDefaults`.
private final class FakeColumnLayoutStore: PanelColumnLayoutStoring, @unchecked Sendable {

    private let lock = NSLock()
    private(set) var saves: [(left: PanelColumnLayout, right: PanelColumnLayout)] = []
    private let stored: (left: PanelColumnLayout, right: PanelColumnLayout)?

    init(stored: (left: PanelColumnLayout, right: PanelColumnLayout)? = nil) {
        self.stored = stored
    }

    func save(left: PanelColumnLayout, right: PanelColumnLayout) {
        lock.withLock { saves.append((left, right)) }
    }

    func load() -> (left: PanelColumnLayout, right: PanelColumnLayout)? { stored }
}

@MainActor
struct PanelColumnLayoutModelTests {

    @Test func bothPanelsStartFromTheDefaultsWhenNothingWasEverSaved() {
        // Arrange & Act
        let model = PanelColumnLayoutModel(store: FakeColumnLayoutStore())

        // Assert
        #expect(model.layout(for: .left) == .defaults)
        #expect(model.layout(for: .right) == .defaults)
    }

    @Test func aLayoutInProgressIsVisibleButNotYetWrittenToStorage() {
        // Arrange — this is every frame of a live drag.
        let store = FakeColumnLayoutStore()
        let model = PanelColumnLayoutModel(store: store)
        let widened = PanelColumnLayout.defaults.resizing(dividerAfter: 1, by: 40, availableWidth: 800)

        // Act
        model.setLayout(widened, for: .left)

        // Assert
        #expect(model.layout(for: .left) == widened)
        #expect(store.saves.isEmpty)
    }

    @Test func committingWritesBothPanelsOnce() {
        // Arrange
        let store = FakeColumnLayoutStore()
        let model = PanelColumnLayoutModel(store: store)
        let widened = PanelColumnLayout.defaults.resizing(dividerAfter: 1, by: 40, availableWidth: 800)
        model.setLayout(widened, for: .left)

        // Act — the end of the drag.
        model.commit()

        // Assert
        #expect(store.saves.count == 1)
        #expect(store.saves.first?.left == widened)
        #expect(store.saves.first?.right == .defaults)
    }

    @Test func aPreviouslySavedLayoutIsRestoredOnLaunch() {
        // Arrange
        let reordered = PanelColumnLayout.defaults.moving(from: 3, to: 1)
        let store = FakeColumnLayoutStore(stored: (left: reordered, right: .defaults))

        // Act
        let model = PanelColumnLayoutModel(store: store)

        // Assert
        #expect(model.layout(for: .left) == reordered)
        #expect(model.layout(for: .right) == .defaults)
    }

    @Test func changingOnePanelLeavesTheOtherAlone() {
        // Arrange
        let model = PanelColumnLayoutModel(store: FakeColumnLayoutStore())

        // Act
        model.setLayout(PanelColumnLayout.defaults.moving(from: 3, to: 1), for: .right)

        // Assert
        #expect(model.layout(for: .left) == .defaults)
        #expect(model.layout(for: .right).columns == [.name, .kind, .size, .dateModified])
    }
}
