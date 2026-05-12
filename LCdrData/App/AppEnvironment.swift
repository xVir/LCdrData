import Foundation

/// Holds application-wide services shared across every window. Per-window state
/// lives in `AppState`, owned by each `WindowRootView`.
@MainActor
final class AppEnvironment {

    let configuration: ConfigurationService
    let bookmarkStore: BookmarkStoreProtocol
    weak var mostRecentAppState: AppState?

    init() {
        let configuration = ConfigurationService()
        try? configuration.load()
        self.configuration = configuration
        self.bookmarkStore = BookmarkStore()
    }

    init(configuration: ConfigurationService, bookmarkStore: BookmarkStoreProtocol) {
        self.configuration = configuration
        self.bookmarkStore = bookmarkStore
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
