import Foundation
import Testing
@testable import Services

nonisolated final class RecordingOpenCommand: OpenCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(name: String, directory: URL)] = []
    var error: Error?

    var invocations: [(name: String, directory: URL)] {
        lock.withLock { recorded }
    }

    func run(applicationName: String, directory: URL) async throws {
        lock.withLock { recorded.append((name: applicationName, directory: directory)) }
        if let error {
            throw error
        }
    }
}

nonisolated final class RecordingApplicationActivator: ApplicationActivating, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var bundleIDs: [String] {
        lock.withLock { recorded }
    }

    func bringForward(bundleIdentifier: String) async {
        lock.withLock { recorded.append(bundleIdentifier) }
    }
}

struct TerminalOpeningServiceTests {

    private let directory = URL(fileURLWithPath: "/Users/me/projects/myrepo")
    private let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    private let ghostty = URL(fileURLWithPath: "/Applications/Ghostty.app")
    private let other = URL(fileURLWithPath: "/Applications/Other.app")

    @Test func macOSTerminalIsHandedTheFolderAndComesForward() async {
        let commands = RecordingOpenCommand()
        let activator = RecordingApplicationActivator()
        let workspace = FakeWorkspace(installedApplications: [
            "com.apple.Terminal": terminal
        ])
        let service = TerminalOpeningService(openCommand: commands, workspace: workspace, activator: activator)

        await service.openInNewTab(directory: directory, applicationBundleID: "com.apple.Terminal")

        #expect(commands.invocations.isEmpty)
        #expect(workspace.applicationOpens.count == 1)
        #expect(workspace.applicationOpens.first?.file == directory)
        #expect(workspace.applicationOpens.first?.application == terminal)
        #expect(activator.bundleIDs == ["com.apple.Terminal"])
    }

    @Test func ghosttyUsesOpenWithTheFolderAndComesForward() async {
        let commands = RecordingOpenCommand()
        let activator = RecordingApplicationActivator()
        let workspace = FakeWorkspace(installedApplications: [
            "com.mitchellh.ghostty": ghostty
        ])
        let service = TerminalOpeningService(openCommand: commands, workspace: workspace, activator: activator)

        await service.openInNewTab(directory: directory, applicationBundleID: "com.mitchellh.ghostty")

        #expect(commands.invocations.count == 1)
        #expect(commands.invocations.first?.name == "Ghostty")
        #expect(commands.invocations.first?.directory == directory)
        #expect(workspace.applicationOpens.isEmpty)
        #expect(activator.bundleIDs == ["com.mitchellh.ghostty"])
    }

    @Test func ghosttyOpenArgumentsKeepThePathAsOneArgument() {
        let quoted = URL(fileURLWithPath: "/Users/me/My \"Files\"")

        let arguments = SystemOpenCommandRunner.arguments(applicationName: "Ghostty", directory: quoted)

        #expect(arguments == ["-a", "Ghostty", "/Users/me/My \"Files\""])
    }

    @Test func anUnknownInstalledAppIsHandedTheFolderAndComesForward() async {
        let commands = RecordingOpenCommand()
        let activator = RecordingApplicationActivator()
        let workspace = FakeWorkspace(installedApplications: [
            "com.example.Other": other
        ])
        let service = TerminalOpeningService(openCommand: commands, workspace: workspace, activator: activator)

        await service.openInNewTab(directory: directory, applicationBundleID: "com.example.Other")

        #expect(commands.invocations.isEmpty)
        #expect(workspace.applicationOpens.count == 1)
        #expect(workspace.applicationOpens.first?.file == directory)
        #expect(workspace.applicationOpens.first?.application == other)
        #expect(activator.bundleIDs == ["com.example.Other"])
    }

    @Test func aMissingApplicationDoesNothing() async {
        let commands = RecordingOpenCommand()
        let activator = RecordingApplicationActivator()
        let workspace = FakeWorkspace()
        let service = TerminalOpeningService(openCommand: commands, workspace: workspace, activator: activator)

        await service.openInNewTab(directory: directory, applicationBundleID: "com.mitchellh.ghostty")

        #expect(commands.invocations.isEmpty)
        #expect(workspace.applicationOpens.isEmpty)
        #expect(activator.bundleIDs.isEmpty)
    }

    @Test func aFailedOpenCommandDoesNotBringGhosttyForward() async {
        let commands = RecordingOpenCommand()
        commands.error = OpenCommandError.failed(1)
        let activator = RecordingApplicationActivator()
        let workspace = FakeWorkspace(installedApplications: [
            "com.mitchellh.ghostty": ghostty
        ])
        let service = TerminalOpeningService(openCommand: commands, workspace: workspace, activator: activator)

        await service.openInNewTab(directory: directory, applicationBundleID: "com.mitchellh.ghostty")

        #expect(commands.invocations.count == 1)
        #expect(workspace.applicationOpens.isEmpty)
        #expect(activator.bundleIDs.isEmpty)
    }
}
