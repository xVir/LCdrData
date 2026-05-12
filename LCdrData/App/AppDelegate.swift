import AppKit

/// Terminates the app when the last window is closed, matching the behavior
/// expected from a single-window utility like a file manager.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
