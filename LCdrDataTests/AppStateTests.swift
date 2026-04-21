import Testing
import Foundation
@testable import LCdrData

// MARK: - Mock Panel Path Store

/// In-memory mock of PanelPathStoreProtocol for testing.
nonisolated final class MockPanelPathStore: PanelPathStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _savedLeft: String?
    private var _savedRight: String?
    private let _restoreResult: (left: URL, right: URL)?

    nonisolated init(restoreResult: (left: URL, right: URL)? = nil) {
        self._restoreResult = restoreResult
    }

    func save(leftPath: String, rightPath: String) {
        lock.withLock {
            _savedLeft = leftPath
            _savedRight = rightPath
        }
    }

    func restore() -> (left: URL, right: URL)? {
        return _restoreResult
    }

    var savedLeft: String? { lock.withLock { _savedLeft } }
    var savedRight: String? { lock.withLock { _savedRight } }
}

// MARK: - Tests

@MainActor
struct AppStateTests {

    @Test func defaultInitStartsWithLeftActive() {
        // Arrange & Act
        let state = AppState()

        // Assert
        #expect(state.activePanel == .left)
    }

    @Test func activePanelViewModelReturnsCorrectSide() {
        // Arrange
        let state = AppState()

        // Assert
        #expect(state.activePanelViewModel.side == .left)
        #expect(state.inactivePanelViewModel.side == .right)
    }

    @Test func switchActivePanelToggles() {
        // Arrange
        let state = AppState()
        #expect(state.activePanel == .left)

        // Act
        state.switchActivePanel()

        // Assert
        #expect(state.activePanel == .right)
        #expect(state.activePanelViewModel.side == .right)
        #expect(state.inactivePanelViewModel.side == .left)

        // Act again
        state.switchActivePanel()

        // Assert
        #expect(state.activePanel == .left)
    }

    @Test func customDirectories() {
        // Arrange & Act
        let left = URL(fileURLWithPath: "/Users/test/Documents")
        let right = URL(fileURLWithPath: "/Users/test/Downloads")
        let store = MockPanelPathStore(restoreResult: nil)
        let state = AppState(
            leftDirectory: left,
            rightDirectory: right,
            panelPathStore: store
        )

        // Assert
        #expect(state.leftPanel.state.currentDirectory == left)
        #expect(state.rightPanel.state.currentDirectory == right)
    }

    // MARK: - Panel Path Persistence

    @Test func savePanelPathsWritesToStore() {
        // Arrange
        let store = MockPanelPathStore()
        let state = AppState(
            leftDirectory: URL(fileURLWithPath: "/tmp/left"),
            rightDirectory: URL(fileURLWithPath: "/tmp/right"),
            panelPathStore: store
        )

        // Act
        state.savePanelPaths()

        // Assert
        #expect(store.savedLeft == "/tmp/left")
        #expect(store.savedRight == "/tmp/right")
    }

    @Test func restoresPanelPathsFromStore() {
        // Arrange — store returns previously saved paths that exist on disk
        let store = MockPanelPathStore(restoreResult: (
            left: URL(fileURLWithPath: "/tmp"),
            right: URL(fileURLWithPath: "/var")
        ))

        // Act
        let state = AppState(panelPathStore: store)

        // Assert — panels should use the restored paths
        #expect(state.leftPanel.state.currentDirectory.path == "/tmp")
        #expect(state.rightPanel.state.currentDirectory.path == "/private/var"
                || state.rightPanel.state.currentDirectory.path == "/var")
    }

    @Test func fallsBackToDefaultWhenStoreReturnsNil() {
        // Arrange — store returns nil (no saved paths or paths don't exist)
        let store = MockPanelPathStore(restoreResult: nil)
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Act
        let state = AppState(panelPathStore: store)

        // Assert — panels should use the default (home directory)
        #expect(state.leftPanel.state.currentDirectory == home)
        #expect(state.rightPanel.state.currentDirectory == home)
    }

    @Test func saveThenRestoreRoundTrip() {
        // Arrange — use real PanelPathStore with an isolated UserDefaults suite
        let defaults = UserDefaults(suiteName: "com.xvir.LCdrData.test.\(UUID())")!
        let store = PanelPathStore(defaults: defaults)

        let state = AppState(
            leftDirectory: URL(fileURLWithPath: "/tmp"),
            rightDirectory: URL(fileURLWithPath: "/var"),
            panelPathStore: store
        )

        // Act — save
        state.savePanelPaths()

        // Act — restore with a new store instance pointing at the same defaults
        let store2 = PanelPathStore(defaults: defaults)
        let restored = store2.restore()

        // Assert
        #expect(restored != nil)
        #expect(restored?.left.path == "/tmp")
        // /var may resolve to /private/var on macOS
        #expect(restored?.right.path == "/var" || restored?.right.path == "/private/var")

        // Cleanup
        defaults.removePersistentDomain(forName: defaults.description)
    }
}
