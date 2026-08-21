import AppKit
import Services
import ViewModels
import AppEnvironment
import Views

/// Terminates the app when the last window is closed, matching the behavior
/// expected from a single-window utility like a file manager.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The app-wide environment, injected by `LCdrDataApp` so that
    /// `applicationWillTerminate` can release the security scopes acquired at
    /// launch via `AppEnvironment.start()`.
    var environment: AppEnvironment?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.releaseAllScopes()
    }
}
