import Testing
import Foundation
@testable import Core
@testable import Services

private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "PanelSessionStoreTests-\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

struct PanelSessionStoreTests {

    @Test func loadReturnsNilBeforeAnythingIsRecorded() {
        // Arrange
        let store = PanelSessionStore(defaults: makeIsolatedDefaults())

        // Act & Assert
        #expect(store.loadLastPaths() == nil)
    }

    @Test func savedPathsSurviveANewStoreOverTheSameDefaults() {
        // Arrange — a second store stands in for the next launch.
        let defaults = makeIsolatedDefaults()
        let store = PanelSessionStore(defaults: defaults)

        // Act
        store.save(leftPath: "/Users/dskachkov/Projects", rightPath: "/Users/dskachkov/Downloads")
        let reloaded = PanelSessionStore(defaults: defaults).loadLastPaths()

        // Assert
        #expect(reloaded?.left == "/Users/dskachkov/Projects")
        #expect(reloaded?.right == "/Users/dskachkov/Downloads")
    }

    @Test func savingAgainReplacesThePreviousPair() {
        // Arrange
        let store = PanelSessionStore(defaults: makeIsolatedDefaults())
        store.save(leftPath: "/a", rightPath: "/b")

        // Act
        store.save(leftPath: "/c", rightPath: "/d")

        // Assert
        #expect(store.loadLastPaths()?.left == "/c")
        #expect(store.loadLastPaths()?.right == "/d")
    }

    @Test func emptyPathsAreTreatedAsNothingRecorded() {
        // Arrange
        let store = PanelSessionStore(defaults: makeIsolatedDefaults())

        // Act
        store.save(leftPath: "", rightPath: "/b")

        // Assert
        #expect(store.loadLastPaths() == nil)
    }
}
