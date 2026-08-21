import Testing
import AppKit
@testable import AppEnvironment
@testable import LCdrData
@testable import Services
@testable import TestSupport

@MainActor
struct AppDelegateTests {

    @Test func applicationWillTerminateReleasesAllScopes() async {
        // Arrange
        let store = FakeBookmarkStore()
        store.save(url: URL(fileURLWithPath: "/a", isDirectory: true))
        store.save(url: FileManager.default.homeDirectoryForCurrentUser)
        let activator = RecordingScopeActivator()
        let env = AppEnvironment(
            configuration: ConfigurationService(),
            bookmarkStore: store,
            sandboxAccess: SandboxAccessService(
                presenter: FakeAccessPresenter(result: nil),
                bookmarkStore: store
            ),
            scopeActivator: activator
        )
        await env.start()
        let delegate = AppDelegate()
        delegate.environment = env

        // Act
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        // Assert
        #expect(env.activeScopes.isEmpty)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Set(activator.stopped.map(\.path)) == ["/a", home])
    }
}
