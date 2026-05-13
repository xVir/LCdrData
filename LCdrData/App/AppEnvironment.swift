import Foundation

/// Brackets `startAccessingSecurityScopedResource` so tests can stand in for
/// the kernel-backed call without acquiring real scopes.
protocol SecurityScopeActivating: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

/// Production activator: forwards to the URL extension methods.
struct SystemSecurityScopeActivator: SecurityScopeActivating {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

/// Holds application-wide services shared across every window. Per-window state
/// lives in `AppState`, owned by each `WindowRootView`.
@MainActor
final class AppEnvironment {

    let configuration: ConfigurationService
    let bookmarkStore: BookmarkStoreProtocol
    let sandboxAccess: SandboxAccessService
    let scopeActivator: SecurityScopeActivating
    weak var mostRecentAppState: AppState?

    private(set) var activeScopes: [URL] = []
    private var hasStarted: Bool = false

    init() {
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
    }

    init(
        configuration: ConfigurationService,
        bookmarkStore: BookmarkStoreProtocol,
        sandboxAccess: SandboxAccessService? = nil,
        scopeActivator: SecurityScopeActivating = SystemSecurityScopeActivator()
    ) {
        self.configuration = configuration
        self.bookmarkStore = bookmarkStore
        self.sandboxAccess = sandboxAccess ?? SandboxAccessService(
            presenter: NSOpenPanelAccessPresenter(),
            bookmarkStore: bookmarkStore
        )
        self.scopeActivator = scopeActivator
    }

    /// Acquires security scope on every bookmark currently in the store.
    /// Idempotent — subsequent calls are no-ops. Bookmarks that fail to start
    /// scope are silently skipped (they remain in the store and may succeed
    /// on a later launch — e.g. an unmounted volume).
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        let urls = bookmarkStore.allBookmarkURLs()
        for url in urls where scopeActivator.startAccessing(url) {
            activeScopes.append(url)
        }
    }

    /// Releases every scope acquired via `start()` or via a runtime grant.
    /// Call from `applicationWillTerminate`.
    func releaseAllScopes() {
        for url in activeScopes {
            scopeActivator.stopAccessing(url)
        }
        activeScopes.removeAll()
    }

    /// Builds a session for a window that has no preserved state — e.g. on
    /// Cmd+N, or the very first window on a fresh launch. Copies the frontmost
    /// window's panel directories when one is recorded.
    func makeFreshSession() -> PanelSession {
        if let frontmost = mostRecentAppState {
            return PanelSession(
                leftPath: frontmost.leftPanel.state.currentDirectory.path,
                rightPath: frontmost.rightPanel.state.currentDirectory.path
            )
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return PanelSession(leftPath: home, rightPath: home)
    }
}
