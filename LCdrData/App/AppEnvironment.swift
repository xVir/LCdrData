import Foundation
import Models
import Services
import ViewModels

/// Brackets `startAccessingSecurityScopedResource` so tests can stand in for
/// the kernel-backed call without acquiring real scopes.
package protocol SecurityScopeActivating: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

/// Production activator: forwards to the URL extension methods.
package struct SystemSecurityScopeActivator: SecurityScopeActivating {
    package func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }
    package func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

/// Holds application-wide services shared across every window. Per-window state
/// lives in `AppState`, owned by each `WindowRootView`.
@MainActor
package final class AppEnvironment {

    package let configuration: ConfigurationService
    package let bookmarkStore: BookmarkStoreProtocol
    package let sandboxAccess: SandboxAccessService
    package let scopeActivator: SecurityScopeActivating
    package let sessionStore: PanelSessionStoring
    /// Shared by every window, so the columns look the same wherever you look.
    package let columnLayouts: PanelColumnLayoutModel
    package weak var mostRecentAppState: AppState?

    package private(set) var activeScopes: [URL] = []
    private var hasStarted: Bool = false

    package init() {
        let configuration = ConfigurationService()
        try? configuration.load()
        self.configuration = configuration
        let bookmarkStore = BookmarkStore()
        self.bookmarkStore = bookmarkStore
        self.sandboxAccess = SandboxAccessService(
            presenter: NSOpenPanelAccessPresenter(),
            bookmarkStore: bookmarkStore
        )
        self.scopeActivator = SystemSecurityScopeActivator()
        self.sessionStore = PanelSessionStore()
        self.columnLayouts = PanelColumnLayoutModel()
    }

    package init(
        configuration: ConfigurationService,
        bookmarkStore: BookmarkStoreProtocol,
        sandboxAccess: SandboxAccessService? = nil,
        scopeActivator: SecurityScopeActivating = SystemSecurityScopeActivator(),
        sessionStore: PanelSessionStoring = PanelSessionStore(),
        columnLayouts: PanelColumnLayoutModel = PanelColumnLayoutModel()
    ) {
        self.configuration = configuration
        self.bookmarkStore = bookmarkStore
        self.sandboxAccess = sandboxAccess ?? SandboxAccessService(
            presenter: NSOpenPanelAccessPresenter(),
            bookmarkStore: bookmarkStore
        )
        self.scopeActivator = scopeActivator
        self.sessionStore = sessionStore
        self.columnLayouts = columnLayouts
    }

    /// Acquires security scope on every bookmark currently in the store, then
    /// presents the startup Home prompt if no stored bookmark covers `~`.
    /// Idempotent — subsequent calls are no-ops. Bookmarks that fail to start
    /// scope are silently skipped (they remain in the store and may succeed
    /// on a later launch — e.g. an unmounted volume).
    package func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        let urls = bookmarkStore.allBookmarkURLs()
        for url in urls where scopeActivator.startAccessing(url) {
            activeScopes.append(url)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        if bookmarkStore.bookmarkCovering(url: home) == nil {
            if let granted = await sandboxAccess.requestAccessIfNeeded(context: .startup),
               scopeActivator.startAccessing(granted) {
                activeScopes.append(granted)
            }
        }
    }

    /// Releases every scope acquired via `start()` or via a runtime grant.
    /// Call from `applicationWillTerminate`.
    package func releaseAllScopes() {
        for url in activeScopes {
            scopeActivator.stopAccessing(url)
        }
        activeScopes.removeAll()
    }

    /// Builds a session for a window that has no preserved state — e.g. on
    /// Cmd+N, or the very first window on a fresh launch. Prefers the frontmost
    /// window's directories (so Cmd+N opens beside what you are looking at),
    /// then the directories recorded on the previous run, and only falls back to
    /// Home on a first launch.
    package func makeFreshSession() -> PanelSession {
        if let frontmost = mostRecentAppState {
            return PanelSession(
                leftPath: frontmost.leftPanel.state.location.persistentDirectory.path,
                rightPath: frontmost.rightPanel.state.location.persistentDirectory.path,
                leftLocation: frontmost.leftPanel.state.location,
                rightLocation: frontmost.rightPanel.state.location
            )
        }
        if let last = sessionStore.loadLastPaths() {
            return PanelSession(leftPath: last.left, rightPath: last.right)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return PanelSession(leftPath: home, rightPath: home)
    }

    /// Records a window's directories as the ones to resume on the next launch.
    package func rememberLastSession(_ session: PanelSession) {
        sessionStore.save(leftPath: session.leftPath, rightPath: session.rightPath)
    }
}
