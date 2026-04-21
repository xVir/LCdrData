import AppKit

/// Terminates the app when the last window is closed, matching the behavior
/// expected from a single-window utility like a file manager.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Set by `LCdrDataApp` so the delegate can save state on quit.
    var appState: AppState?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.savePanelPaths()
    }
}
