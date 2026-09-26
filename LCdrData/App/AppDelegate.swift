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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment, environment.hasUnfinishedBackgroundTasks else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "File operations are still running"
        alert.informativeText = "Closing stops them. Items already finished stay finished, and operations that have not started will not run."
        alert.addButton(withTitle: "Cancel and Close")
        alert.addButton(withTitle: "Keep Open")
        if alert.runModal() == .alertFirstButtonReturn {
            environment.cancelUnfinishedBackgroundTasks()
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.releaseAllScopes()
    }
}
