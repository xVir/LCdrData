import Testing
import Foundation
import SwiftUI
@testable import Core
@testable import Services
@testable import ViewModels

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

    // MARK: - Execution routes through file operations

    @Test func trashRequestsDeleteConfirmation() {
        // Arrange
        let a = file("a.txt")
        let appState = makeAppState(items: [a], selected: [a.id])

        // Act
        appState.commands.perform(.trash)

        // Assert
        #expect(appState.fileOperations.showConfirmationDialog)
        guard case .delete(let urls)? = appState.fileOperations.pendingOperationType else {
            Issue.record("expected a pending delete operation")
            return
        }
        #expect(urls == [a.url])
    }

    @Test func copyRequestsCopyConfirmation() {
        // Arrange
        let a = file("a.txt")
        let appState = makeAppState(items: [a], selected: [a.id])

        // Act
        appState.commands.perform(.copy)

        // Assert
        #expect(appState.fileOperations.showConfirmationDialog)
        guard case .copy(let sources, _)? = appState.fileOperations.pendingOperationType else {
            Issue.record("expected a pending copy operation")
            return
        }
        #expect(sources == [a.url])
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
