import Foundation

/// Holds application-wide services shared across every window. Per-window state
/// lives in `AppState`, owned by each `WindowRootView`.
@MainActor
final class AppEnvironment {

    let configuration: ConfigurationService
    let bookmarkStore: BookmarkStoreProtocol
    let sandboxAccess: SandboxAccessService
    weak var mostRecentAppState: AppState?

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
    }

    init(
        configuration: ConfigurationService,
        bookmarkStore: BookmarkStoreProtocol,
        sandboxAccess: SandboxAccessService? = nil
    ) {
        self.configuration = configuration
        self.bookmarkStore = bookmarkStore
        self.sandboxAccess = sandboxAccess ?? SandboxAccessService(
            presenter: NSOpenPanelAccessPresenter(),
            bookmarkStore: bookmarkStore
        )
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
