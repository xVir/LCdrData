import Testing
import Foundation
@testable import AppEnvironment
@testable import Models
@testable import Services
@testable import ViewModels
@testable import TestSupport

@MainActor
struct AppEnvironmentTests {

    @Test func makeFreshSessionUsesHomeOnAFirstLaunch() {
        // Arrange — nothing recorded by a previous run.
        let env = makeEnvironment(sessionStore: FakePanelSessionStore())

        // Act
        let session = env.makeFreshSession()

        // Assert
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(session.leftPath == home)
        #expect(session.rightPath == home)
    }

    @Test func makeFreshSessionResumesThePreviousRunsDirectories() {
        // Arrange
        let store = FakePanelSessionStore()
        store.save(leftPath: "/Users/test/Projects", rightPath: "/Users/test/Downloads")
        let env = makeEnvironment(sessionStore: store)

        // Act
        let session = env.makeFreshSession()

        // Assert
        #expect(session.leftPath == "/Users/test/Projects")
        #expect(session.rightPath == "/Users/test/Downloads")
    }

    @Test func rememberLastSessionRecordsBothPaths() {
        // Arrange
        let store = FakePanelSessionStore()
        let env = makeEnvironment(sessionStore: store)

        // Act
        env.rememberLastSession(
            PanelSession(leftPath: "/Users/test/a", rightPath: "/Users/test/b")
        )

        // Assert
        #expect(store.loadLastPaths()?.left == "/Users/test/a")
        #expect(store.loadLastPaths()?.right == "/Users/test/b")
    }

    @Test func frontmostWindowWinsOverThePreviousRun() {
        // Arrange — Cmd+N should open beside what the user is looking at now.
        let store = FakePanelSessionStore()
        store.save(leftPath: "/stale/left", rightPath: "/stale/right")
        let env = makeEnvironment(sessionStore: store)
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

    private func makeEnvironment(sessionStore: PanelSessionStoring) -> AppEnvironment {
        AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: FakeBookmarkStore(),
            sandboxAccess: SandboxAccessService(
                presenter: FakeAccessPresenter(result: nil),
                bookmarkStore: FakeBookmarkStore()
            ),
            scopeActivator: RecordingScopeActivator(),
            sessionStore: sessionStore
        )
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

    @Test func archiveLocationIsClonedLiveButCollapsesWhenEncodedForRestore() throws {
        // Arrange
        let env = makeEnvironment(sessionStore: FakePanelSessionStore())
        let frontmost = AppState(
            leftDirectory: URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true),
            rightDirectory: URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        )
        let archiveLocation = BrowseLocation.zipArchive(
            container: URL(fileURLWithPath: "/Users/test/Documents/files.zip"),
            internalPath: "folder"
        )
        frontmost.leftPanel.state.location = archiveLocation
        env.mostRecentAppState = frontmost

        // Act
        let liveSession = env.makeFreshSession()
        let restoredSession = try JSONDecoder().decode(
            PanelSession.self,
            from: JSONEncoder().encode(liveSession)
        )

        // Assert
        #expect(liveSession.leftLocation == archiveLocation)
        #expect(liveSession.leftPath == "/Users/test/Documents")
        #expect(restoredSession.leftLocation == nil)
        #expect(restoredSession.leftPath == "/Users/test/Documents")

        _ = frontmost
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

/// In-memory session store so restore expectations don't touch real defaults.
nonisolated final class FakePanelSessionStore: PanelSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: (left: String, right: String)?

    func save(leftPath: String, rightPath: String) {
        guard !leftPath.isEmpty, !rightPath.isEmpty else { return }
        lock.withLock { paths = (leftPath, rightPath) }
    }

    func loadLastPaths() -> (left: String, right: String)? {
        lock.withLock { paths }
    }
}
