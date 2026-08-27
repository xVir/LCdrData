import AppKit
import Foundation

/// The slice of `NSWorkspace` that opening a file needs. Behind a protocol so
/// the resolve-or-fall-back decision can be tested without launching anything.
package nonisolated protocol WorkspaceApplicationOpening: Sendable {
    /// Location of the installed application with `bundleID`, or `nil` if none is.
    func applicationURL(forBundleIdentifier bundleID: String) -> URL?
    /// Opens `url` with whichever application the system considers its handler.
    func open(_ url: URL)
    /// Opens `url` with the application at `applicationURL`.
    func open(_ url: URL, withApplicationAt applicationURL: URL) async
}

/// Production workspace: forwards to `NSWorkspace.shared`.
package nonisolated struct SystemWorkspace: WorkspaceApplicationOpening {
    package init() {}

    package func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    package func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    package func open(_ url: URL, withApplicationAt applicationURL: URL) async {
        _ = try? await NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

/// Opens a file in another application. Behind a protocol so tests can observe
/// what F4 asked for without launching anything.
package nonisolated protocol FileOpeningServiceProtocol: Sendable {
    /// Opens `url`, preferring the application with `bundleID` when one is given.
    func open(_ url: URL, preferredApplicationBundleID bundleID: String?) async
}

/// Concrete implementation backed by `NSWorkspace`.
package nonisolated final class FileOpeningService: FileOpeningServiceProtocol, Sendable {

    private let workspace: any WorkspaceApplicationOpening

    package init(workspace: any WorkspaceApplicationOpening = SystemWorkspace()) {
        self.workspace = workspace
    }

    package func open(_ url: URL, preferredApplicationBundleID bundleID: String?) async {
        guard
            let bundleID,
            let applicationURL = workspace.applicationURL(forBundleIdentifier: bundleID)
        else {
            workspace.open(url)
            return
        }
        await workspace.open(url, withApplicationAt: applicationURL)
    }
}
