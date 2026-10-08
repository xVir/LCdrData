import Testing
import Foundation
import SwiftUI
@testable import Models
@testable import Utilities
@testable import Services
@testable import ViewModels
@testable import Bindings

@MainActor
struct CommandRunnerTests {

    // MARK: - Fixtures

    private func file(_ name: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/dir/\(name)"), name: name, isDirectory: false)
    }

    /// Builds an AppState with the left panel populated and active.
    private func makeAppState(
        items: [FileItem],
        selected: Set<UUID>,
        focused: UUID? = nil
    ) -> AppState {
        let appState = AppState()
        appState.activePanel = .left
        appState.leftPanel.state.items = items
        appState.leftPanel.state.cursor = Cursor(focused: focused, selected: selected)
        return appState
    }

    private func directory(_ name: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/dir/\(name)"), name: name, isDirectory: true)
    }

    @Test func openLeftLocationInRightPanelDoesNotChangeTheActivePanel() async throws {
        // Arrange — the right panel is active, and the left panel is sorted by size.
        let opened = FileItem(
            url: URL(fileURLWithPath: "/left/a.txt"),
            name: "a.txt",
            isDirectory: false
        )
        let appState = AppState()
        appState.leftPanel = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/left"),
            sortDescriptor: FileSortDescriptor(column: .size, ascending: false),
            fileSystemService: MockFileSystemService(itemsByPath: ["/left": [opened]])
        )
        appState.rightPanel = PanelViewModel(
            side: .right,
            initialDirectory: URL(fileURLWithPath: "/right"),
            showHiddenFiles: true,
            fileSystemService: MockFileSystemService(itemsByPath: ["/right": [], "/left": [opened]])
        )
        await appState.leftPanel.reload(.fresh)
        await appState.rightPanel.reload(.fresh)
        appState.activePanel = .right

        // Act
        appState.commands.perform(.openLeftLocationInRightPanel)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && appState.rightPanel.state.tabs.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(appState.activePanel == .right)
        #expect(appState.rightPanel.state.tabs.count == 2)
        #expect(appState.rightPanel.state.location == .directory(URL(fileURLWithPath: "/left")))
        #expect(appState.rightPanel.state.sortDescriptor == FileSortDescriptor(column: .size, ascending: false))
        #expect(appState.rightPanel.state.showHiddenFiles)
    }

    // MARK: - Edit enablement

    @Test func editIsDisabledOnAFolderWhenOpenFoldersIsOff() {
        // Arrange
        let folder = directory("reports")
        let appState = makeAppState(items: [folder], selected: [folder.id])
        appState.leftPanel.editorOpenFolders = false

        // Assert
        #expect(appState.commands.isEnabled(.edit) == false)
    }

    @Test func editIsEnabledOnAFolderWhenOpenFoldersIsOn() {
        // Arrange
        let folder = directory("reports")
        let appState = makeAppState(items: [folder], selected: [folder.id])
        appState.leftPanel.editorOpenFolders = true

        // Assert
        #expect(appState.commands.isEnabled(.edit) == true)
    }

    @Test func quickLookStaysDisabledOnAFolderRegardlessOfOpenFolders() {
        // Arrange
        let folder = directory("reports")
        let appState = makeAppState(items: [folder], selected: [folder.id])
        appState.leftPanel.editorOpenFolders = true

        // Assert — open-folders is an F4 setting; F3 is unaffected.
        #expect(appState.commands.isEnabled(.quickLook) == false)
    }

    // MARK: - Execution routes through file operations

    @Test func trashRequestsDeleteConfirmation() {
        // Arrange
        let a = file("a.txt")
        let appState = makeAppState(items: [a], selected: [a.id])

        // Act
        appState.commands.perform(.trash)

        // Assert
        #expect(appState.fileOperations.showConfirmationDialog)
        guard case .browseDelete(let items, let source, false)? =
            appState.fileOperations.pendingOperationType
        else {
            Issue.record("expected a pending delete operation")
            return
        }
        #expect(items == [a])
        #expect(source == appState.leftPanel.state.location)
    }

    @Test func copyRequestsCopyConfirmation() {
        // Arrange
        let a = file("a.txt")
        let appState = makeAppState(items: [a], selected: [a.id])

        // Act
        appState.commands.perform(.copy)

        // Assert
        #expect(appState.fileOperations.showConfirmationDialog)
        guard case .browseCopy(let items, let source, let destination)? =
            appState.fileOperations.pendingOperationType
        else {
            Issue.record("expected a pending copy operation")
            return
        }
        #expect(items == [a])
        #expect(source == appState.leftPanel.state.location)
        #expect(destination == appState.rightPanel.state.location)
    }

    @Test func newFolderShowsDialog() {
        // Arrange
        let appState = makeAppState(items: [], selected: [])

        // Act
        appState.commands.perform(.newFolder)

        // Assert
        #expect(appState.fileOperations.showNewFolderDialog)
    }

    @Test func renameShowsDialogForItem() {
        // Arrange
        let a = file("a.txt")
        let appState = makeAppState(items: [a], selected: [a.id])

        // Act
        appState.commands.perform(.rename(a))

        // Assert
        #expect(appState.fileOperations.showRenameDialog)
        #expect(appState.fileOperations.renameItem == a)
    }

    // MARK: - Enablement

    @Test func selectionCommandsReflectSelection() {
        // Arrange
        let a = file("a.txt")
        let withSelection = makeAppState(items: [a], selected: [a.id])
        let withoutSelection = makeAppState(items: [a], selected: [])

        // Act / Assert
        #expect(withSelection.commands.isEnabled(.copy))
        #expect(withSelection.commands.isEnabled(.trash))
        #expect(!withoutSelection.commands.isEnabled(.copy))
        #expect(!withoutSelection.commands.isEnabled(.trash))
    }

    @Test func renameDisabledForParentRow() {
        // Arrange
        let parent = FileItem.parentEntry(for: URL(fileURLWithPath: "/dir"))
        let appState = makeAppState(items: [parent], selected: [])

        // Act / Assert
        #expect(!appState.commands.isEnabled(.rename(parent)))
    }

    @Test func openInTerminalIsEnabledForASingleFolderAndTheParentRow() {
        let folder = directory("reports")
        let parent = FileItem.parentEntry(for: URL(fileURLWithPath: "/dir"))
        let fileItem = file("a.txt")

        let folderState = makeAppState(items: [folder], selected: [folder.id])
        let parentState = makeAppState(items: [parent], selected: [parent.id])
        let fileState = makeAppState(items: [fileItem], selected: [fileItem.id])
        let both = makeAppState(items: [folder, fileItem], selected: [folder.id, fileItem.id])

        #expect(folderState.commands.isEnabled(.openInTerminal))
        #expect(parentState.commands.isEnabled(.openInTerminal))
        #expect(!fileState.commands.isEnabled(.openInTerminal))
        #expect(!both.commands.isEnabled(.openInTerminal))
    }

    @Test func openInTerminalOnTheParentRowOpensTheFolderBeingShown() async throws {
        let current = URL(fileURLWithPath: "/dir/project")
        let parent = FileItem.parentEntry(for: current)
        let opener = RecordingTerminalOpening()
        let appState = AppState(
            leftDirectory: current,
            configuration: try makeTerminalConfiguration(bundleID: "com.apple.Terminal"),
            sandboxAccess: SandboxAccessService(
                presenter: NoopAccessPresenter(),
                bookmarkStore: BookmarkStore()
            ),
            terminalOpening: opener
        )
        appState.leftPanel.state.items = [parent]
        appState.leftPanel.state.cursor = Cursor(focused: parent.id, selected: [parent.id])

        appState.commands.perform(.openInTerminal)

        var opens = opener.opens
        for _ in 0..<50 where opens.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
            opens = opener.opens
        }

        #expect(opens.count == 1)
        #expect(opens.first?.directory == current)
        #expect(opens.first?.directory != parent.url)
    }

    @Test func openInTerminalOpensTheSelectedFolderWithTheConfiguredApp() async throws {
        let folder = directory("reports")
        let opener = RecordingTerminalOpening()
        let configuration = try makeTerminalConfiguration(bundleID: "com.mitchellh.ghostty")
        let appState = AppState(
            configuration: configuration,
            sandboxAccess: SandboxAccessService(
                presenter: NoopAccessPresenter(),
                bookmarkStore: BookmarkStore()
            ),
            terminalOpening: opener
        )
        appState.leftPanel.state.items = [folder]
        appState.leftPanel.state.cursor = Cursor(focused: folder.id, selected: [folder.id])

        appState.commands.perform(.openInTerminal)

        var opens = opener.opens
        for _ in 0..<50 where opens.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
            opens = opener.opens
        }

        #expect(opens.count == 1)
        #expect(opens.first?.directory == folder.url)
        #expect(opens.first?.bundleID == "com.mitchellh.ghostty")
    }

    @Test func openInTerminalDoesNothingWhenTheSelectionIsAFile() async throws {
        let fileItem = file("a.txt")
        let opener = RecordingTerminalOpening()
        let appState = AppState(
            configuration: try makeTerminalConfiguration(bundleID: "com.apple.Terminal"),
            sandboxAccess: SandboxAccessService(
                presenter: NoopAccessPresenter(),
                bookmarkStore: BookmarkStore()
            ),
            terminalOpening: opener
        )
        appState.leftPanel.state.items = [fileItem]
        appState.leftPanel.state.cursor = Cursor(focused: fileItem.id, selected: [fileItem.id])

        appState.commands.perform(.openInTerminal)

        #expect(opener.opens.isEmpty)
    }

    @Test func alwaysEnabledCommands() {
        // Arrange
        let appState = makeAppState(items: [], selected: [])

        // Act / Assert
        #expect(appState.commands.isEnabled(.selectAll))
        #expect(appState.commands.isEnabled(.newFolder))
        #expect(appState.commands.isEnabled(.goToParent))
    }

    @Test func readOnlyArchiveDisablesMutatingAndFinderCommands() async {
        // Arrange
        let container = URL(fileURLWithPath: "/tmp/files.zip")
        let item = FileItem(
            archiveContainer: container,
            internalPath: "file.txt",
            name: "file.txt",
            isDirectory: false
        )
        let appState = AppState(
            archiveService: MockArchiveService(
                itemsByPath: ["": [item]],
                writable: false
            )
        )
        await appState.leftPanel.navigate(
            to: .zipArchive(container: container, internalPath: "")
        )
        appState.leftPanel.state.cursor = Cursor(focused: item.id, selected: [item.id])

        // Act / Assert
        #expect(!appState.commands.isEnabled(.trash))
        #expect(!appState.commands.isEnabled(.permanentDelete))
        #expect(!appState.commands.isEnabled(.newFolder))
        #expect(!appState.commands.isEnabled(.rename(item)))
        #expect(!appState.commands.isEnabled(.revealInFinder))
    }

    // MARK: - Return activation

    @Test func returnOnArchiveEntersItRatherThanRenamingIt() {
        // Arrange
        let archive = FileItem(
            url: URL(fileURLWithPath: "/dir/files.zip"),
            name: "files.zip",
            isDirectory: false
        )
        let appState = makeAppState(items: [archive], selected: [archive.id])

        // Act
        let command = appState.commands.returnCommand

        // Assert
        #expect(command == .openItem(archive))
    }

    @Test func returnOnRegularFileRenamesIt() {
        // Arrange
        let a = file("a.txt")
        let appState = makeAppState(items: [a], selected: [a.id])

        // Act
        let command = appState.commands.returnCommand

        // Assert
        #expect(command == .rename(a))
    }

    @Test func returnOnDirectoryOpensIt() {
        // Arrange
        let folder = FileItem(
            url: URL(fileURLWithPath: "/dir/sub"),
            name: "sub",
            isDirectory: true
        )
        let appState = makeAppState(items: [folder], selected: [], focused: folder.id)

        // Act
        let command = appState.commands.returnCommand

        // Assert
        #expect(command == .openItem(folder))
    }

    @Test func returnWithoutACursorTargetDoesNothing() {
        // Arrange
        let appState = makeAppState(items: [], selected: [])

        // Act / Assert
        #expect(appState.commands.returnCommand == nil)
    }

    // MARK: - Rename target resolution

    @Test func renameTargetResolvesSingleSelection() {
        // Arrange
        let a = file("a.txt")
        let b = file("b.txt")
        let appState = makeAppState(items: [a, b], selected: [b.id])

        // Act / Assert
        #expect(appState.commands.renameTarget == b)
    }

    @Test func renameTargetNilForMultiSelectionWithoutFocus() {
        // Arrange
        let a = file("a.txt")
        let b = file("b.txt")
        let appState = makeAppState(items: [a, b], selected: [a.id, b.id], focused: nil)

        // Act / Assert
        #expect(appState.commands.renameTarget == nil)
    }

    private func makeTerminalConfiguration(bundleID: String) throws -> ConfigurationService {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataTerminal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let service = ConfigurationService(
            bundle: Bundle.main,
            fileManager: .default,
            configDirectory: tmp,
            defaultKDLTextOverride: """
            terminal {
                default-app "\(bundleID)"
            }

            """
        )
        try service.load()
        return service
    }
}

private nonisolated final class RecordingTerminalOpening: TerminalOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(directory: URL, bundleID: String)] = []

    var opens: [(directory: URL, bundleID: String)] {
        lock.withLock { recorded }
    }

    func openInNewTab(directory: URL, applicationBundleID: String) async {
        lock.withLock {
            recorded.append((directory: directory, bundleID: applicationBundleID))
        }
    }
}

struct CommandCatalogTests {

    @Test func copyBindsToF5WithoutModifiers() {
        // Arrange / Act
        let binding = CommandCatalog.binding(for: .copy)

        // Assert
        #expect(binding?.key.character == KeyboardShortcuts.f5Key.character)
        #expect(binding?.modifiers == [])
    }

    @Test func selectAllBindsToCommandA() {
        // Arrange / Act
        let binding = CommandCatalog.binding(for: .selectAll)

        // Assert
        #expect(binding?.key.character == "a")
        #expect(binding?.modifiers == .command)
    }

    @Test func revealInFinderHasNoShortcut() {
        // Arrange / Act / Assert
        #expect(CommandCatalog.binding(for: .revealInFinder) == nil)
        #expect(CommandCatalog.shortcut(for: .revealInFinder) == nil)
    }
}
