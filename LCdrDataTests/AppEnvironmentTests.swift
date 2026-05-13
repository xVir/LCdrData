import Testing
import Foundation
@testable import LCdrData

@MainActor
struct AppEnvironmentTests {

    @Test func makeFreshSessionUsesHomeWhenNoFrontmostState() {
        // Arrange
        let env = AppEnvironment()

        // Act
        let session = env.makeFreshSession()

        // Assert
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(session.leftPath == home)
        #expect(session.rightPath == home)
    }

    @Test func makeFreshSessionCopiesFromFrontmostState() {
        // Arrange
        let env = AppEnvironment()
        let frontmost = AppState(
            leftDirectory: URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true),
            rightDirectory: URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        )
        env.mostRecentAppState = frontmost

        // Act
        let session = env.makeFreshSession()

        // Assert
        #expect(session.leftPath == "/Users/test/Documents")
        #expect(session.rightPath == "/Users/test/Downloads")

        _ = frontmost  // keep alive — mostRecentAppState is weak
    }

    @Test func startRegistersScopeForEveryStoredBookmark() async {
        // Arrange — bookmark store seeded with two URLs.
        let store = FakeBookmarkStore()
        store.save(url: URL(fileURLWithPath: "/a", isDirectory: true))
        store.save(url: URL(fileURLWithPath: "/b", isDirectory: true))
        let activator = RecordingScopeActivator()
        let env = AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: store,
            scopeActivator: activator
        )

        // Act
        await env.start()

        // Assert — every stored URL is reflected in activeScopes.
        let scopes = Set(env.activeScopes.map(\.path))
        #expect(scopes == ["/a", "/b"])
        #expect(Set(activator.started.map(\.path)) == ["/a", "/b"])
    }

    @Test func releaseAllScopesStopsEveryActiveScope() async {
        // Arrange
        let store = FakeBookmarkStore()
        store.save(url: URL(fileURLWithPath: "/a", isDirectory: true))
        store.save(url: URL(fileURLWithPath: "/b", isDirectory: true))
        let activator = RecordingScopeActivator()
        let env = AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: store,
            scopeActivator: activator
        )
        await env.start()

        // Act
        env.releaseAllScopes()

        // Assert
        #expect(env.activeScopes.isEmpty)
        #expect(Set(activator.stopped.map(\.path)) == ["/a", "/b"])
    }
}

/// Test activator: records calls; pretends `startAccessing` always succeeds.
nonisolated final class RecordingScopeActivator: SecurityScopeActivating, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var started: [URL] = []
    private(set) var stopped: [URL] = []

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock { started.append(url) }
        return true
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { stopped.append(url) }
    }
}
