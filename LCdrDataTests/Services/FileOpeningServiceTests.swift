import Testing
import Foundation
@testable import Services

// MARK: - Fake Workspace

/// Stands in for `NSWorkspace`: resolves only the bundle IDs it was told
/// about, and records every open request instead of launching anything.
nonisolated final class FakeWorkspace: WorkspaceApplicationOpening, @unchecked Sendable {

    private let lock = NSLock()
    private let installedApplications: [String: URL]
    private(set) var systemDefaultOpens: [URL] = []
    private(set) var applicationOpens: [(file: URL, application: URL)] = []

    init(installedApplications: [String: URL] = [:]) {
        self.installedApplications = installedApplications
    }

    func applicationURL(forBundleIdentifier bundleID: String) -> URL? {
        installedApplications[bundleID]
    }

    func open(_ url: URL) {
        lock.withLock { systemDefaultOpens.append(url) }
    }

    func open(_ url: URL, withApplicationAt applicationURL: URL) async {
        lock.withLock { applicationOpens.append((file: url, application: applicationURL)) }
    }
}

// MARK: - Tests

struct FileOpeningServiceTests {

    private let file = URL(fileURLWithPath: "/tmp/notes.txt")
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    @Test func opensWithTheConfiguredApplicationWhenItIsInstalled() async {
        // Arrange
        let workspace = FakeWorkspace(installedApplications: ["com.apple.TextEdit": textEdit])
        let service = FileOpeningService(workspace: workspace)

        // Act
        await service.open(file, preferredApplicationBundleID: "com.apple.TextEdit")

        // Assert
        #expect(workspace.applicationOpens.count == 1)
        #expect(workspace.applicationOpens.first?.file == file)
        #expect(workspace.applicationOpens.first?.application == textEdit)
        #expect(workspace.systemDefaultOpens.isEmpty)
    }

    @Test func fallsBackToTheSystemDefaultWhenTheConfiguredApplicationIsMissing() async {
        // Arrange — nothing is installed, so the bundle ID cannot resolve.
        let workspace = FakeWorkspace()
        let service = FileOpeningService(workspace: workspace)

        // Act
        await service.open(file, preferredApplicationBundleID: "com.example.NotInstalled")

        // Assert
        #expect(workspace.systemDefaultOpens == [file])
        #expect(workspace.applicationOpens.isEmpty)
    }

    @Test func opensWithTheSystemDefaultWhenNoApplicationIsPreferred() async {
        // Arrange
        let workspace = FakeWorkspace(installedApplications: ["com.apple.TextEdit": textEdit])
        let service = FileOpeningService(workspace: workspace)

        // Act
        await service.open(file, preferredApplicationBundleID: nil)

        // Assert
        #expect(workspace.systemDefaultOpens == [file])
        #expect(workspace.applicationOpens.isEmpty)
    }
}
