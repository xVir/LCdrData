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
        // Arrange — bookmark store seeded with two URLs *and* the user's
        // Home directory so start() doesn't fire the startup prompt.
        let store = FakeBookmarkStore()
        store.save(url: URL(fileURLWithPath: "/a", isDirectory: true))
        store.save(url: URL(fileURLWithPath: "/b", isDirectory: true))
        store.save(url: FileManager.default.homeDirectoryForCurrentUser)
        let activator = RecordingScopeActivator()
        let sandbox = SandboxAccessService(
            presenter: FakeAccessPresenter(result: nil),
            bookmarkStore: store
        )
        let env = AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: store,
            sandboxAccess: sandbox,
            scopeActivator: activator
        )

        // Act
        await env.start()

        // Assert — every stored URL is reflected in activeScopes.
        let scopes = Set(env.activeScopes.map(\.path))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(scopes == ["/a", "/b", home])
        #expect(Set(activator.started.map(\.path)) == ["/a", "/b", home])
    }

    @Test func startPromptsForHomeWhenNoBookmarkCoversIt() async {
        // Arrange — empty store; record presenter calls.
        let store = FakeBookmarkStore()
        let presenter = FakeAccessPresenter(result: nil)
        let sandbox = SandboxAccessService(presenter: presenter, bookmarkStore: store)
        let env = AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: store,
            sandboxAccess: sandbox,
            scopeActivator: RecordingScopeActivator()
        )

        // Act
        await env.start()

        // Assert — presenter was invoked exactly once with .startup.
        #expect(presenter.presentedContexts.count == 1)
        #expect(presenter.presentedContexts.first == .startup)
    }

    @Test func startSkipsHomePromptWhenBookmarkAlreadyCoversIt() async {
        // Arrange — store has a bookmark covering the user's Home directory.
        let store = FakeBookmarkStore()
        store.save(url: FileManager.default.homeDirectoryForCurrentUser)
        let presenter = FakeAccessPresenter(result: nil)
        let sandbox = SandboxAccessService(presenter: presenter, bookmarkStore: store)
        let env = AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: store,
            sandboxAccess: sandbox,
            scopeActivator: RecordingScopeActivator()
        )

        // Act
        await env.start()

        // Assert — no startup prompt.
        #expect(presenter.presentedContexts.isEmpty)
    }

    @Test func releaseAllScopesStopsEveryActiveScope() async {
        // Arrange
        let store = FakeBookmarkStore()
        store.save(url: URL(fileURLWithPath: "/a", isDirectory: true))
        store.save(url: URL(fileURLWithPath: "/b", isDirectory: true))
        store.save(url: FileManager.default.homeDirectoryForCurrentUser)
        let activator = RecordingScopeActivator()
        let sandbox = SandboxAccessService(
            presenter: FakeAccessPresenter(result: nil),
            bookmarkStore: store
        )
        let env = AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: store,
            sandboxAccess: sandbox,
            scopeActivator: activator
        )
        await env.start()

        // Act
        env.releaseAllScopes()

        // Assert
        #expect(env.activeScopes.isEmpty)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Set(activator.stopped.map(\.path)) == ["/a", "/b", home])
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
