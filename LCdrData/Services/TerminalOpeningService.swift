import AppKit
import Foundation
import Models

package nonisolated enum OpenCommandError: Error, Equatable {
    case failed(Int32)
}

/// Runs `/usr/bin/open -a <application> <directory>`. Behind a protocol so tests
/// never launch a terminal. Ghostty opens a new tab when given a folder this way.
package nonisolated protocol OpenCommandRunning: Sendable {
    func run(applicationName: String, directory: URL) async throws
}

/// Production runner: `open -a Ghostty /path/to/folder`.
package nonisolated struct SystemOpenCommandRunner: OpenCommandRunning {
    package init() {}

    package static func arguments(applicationName: String, directory: URL) -> [String] {
        ["-a", applicationName, directory.standardizedFileURL.path]
    }

    package func run(applicationName: String, directory: URL) async throws {
        let arguments = Self.arguments(applicationName: applicationName, directory: directory)
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw OpenCommandError.failed(process.terminationStatus)
            }
        }.value
    }
}

/// Brings a running application and its windows in front of this one.
package nonisolated protocol ApplicationActivating: Sendable {
    func bringForward(bundleIdentifier: String) async
}

/// Production activator: asks the running app to come forward, including a
/// window that was minimized or behind other windows.
package nonisolated struct SystemApplicationActivator: ApplicationActivating {
    package init() {}

    package func bringForward(bundleIdentifier: String) async {
        let bundleID = bundleIdentifier
        await MainActor.run {
            guard let application = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first
            else {
                return
            }
            application.activate(from: .current, options: [.activateAllWindows])
        }
    }
}

/// Opens a folder in a new tab of the configured terminal application.
package nonisolated protocol TerminalOpening: Sendable {
    func openInNewTab(directory: URL, applicationBundleID: String) async
}

/// Concrete opener. Ghostty is launched with `open -a Ghostty <folder>`.
/// macOS Terminal, and any other installed application, is handed the folder
/// path. Either way the terminal is brought forward afterwards.
package nonisolated final class TerminalOpeningService: TerminalOpening, Sendable {

    private let openCommand: any OpenCommandRunning
    private let workspace: any WorkspaceApplicationOpening
    private let activator: any ApplicationActivating

    package init(
        openCommand: any OpenCommandRunning = SystemOpenCommandRunner(),
        workspace: any WorkspaceApplicationOpening = SystemWorkspace(),
        activator: any ApplicationActivating = SystemApplicationActivator()
    ) {
        self.openCommand = openCommand
        self.workspace = workspace
        self.activator = activator
    }

    package func openInNewTab(directory: URL, applicationBundleID: String) async {
        let bundleID = applicationBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty,
              let applicationURL = workspace.applicationURL(forBundleIdentifier: bundleID)
        else {
            return
        }

        if bundleID == TerminalApplications.ghosttyBundleID {
            do {
                try await openCommand.run(
                    applicationName: TerminalApplications.ghosttyApplicationName,
                    directory: directory
                )
            } catch {
                return
            }
            await activator.bringForward(bundleIdentifier: bundleID)
            return
        }

        await workspace.open(directory, withApplicationAt: applicationURL)
        await activator.bringForward(bundleIdentifier: bundleID)
    }
}
