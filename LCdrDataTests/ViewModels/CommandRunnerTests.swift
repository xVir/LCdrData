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
