import Testing
import Foundation
@testable import Models
@testable import Services

private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "PanelColumnLayoutStoreTests-\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

struct PanelColumnLayoutStoreTests {

    @Test func aResizedColumnComesBackOnTheNextLaunch() {
        // Arrange — a second store over the same defaults stands in for the
        // next launch.
        let defaults = makeIsolatedDefaults()
        let widened = PanelColumnLayout.defaults.resizing(dividerAfter: 1, by: 40, availableWidth: 800)

        // Act
        PanelColumnLayoutStore(defaults: defaults).save(left: widened, right: .defaults)
        let reloaded = PanelColumnLayoutStore(defaults: defaults).load()

        // Assert
        #expect(reloaded?.left == widened)
        #expect(reloaded?.right == .defaults)
    }

    @Test func nothingIsReportedBeforeAnyColumnHasBeenTouched() {
        // Arrange
        let store = PanelColumnLayoutStore(defaults: makeIsolatedDefaults())

        // Act & Assert — the caller falls back to the defaults itself.
        #expect(store.load() == nil)
    }

    @Test func theTwoPanelsKeepSeparateLayouts() {
        // Arrange
        let store = PanelColumnLayoutStore(defaults: makeIsolatedDefaults())
        let reordered = PanelColumnLayout.defaults.moving(from: 3, to: 1)

        // Act
        store.save(left: .defaults, right: reordered)

        // Assert
        #expect(store.load()?.left.columns == [.name, .size, .dateModified, .kind])
        #expect(store.load()?.right.columns == [.name, .kind, .size, .dateModified])
    }

    @Test func unreadableStoredDataIsTreatedAsNothingRecorded() {
        // Arrange — a payload from some other version, or a corrupted write.
        let defaults = makeIsolatedDefaults()
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "panelColumnLayouts")

        // Act & Assert — no throw, no crash, just a fresh start.
        #expect(PanelColumnLayoutStore(defaults: defaults).load() == nil)
    }
}
