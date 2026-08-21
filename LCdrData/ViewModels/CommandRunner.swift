import AppKit
import Foundation
import Models
import Services

/// Executes `Command`s against a window's `AppState`, resolving the active /
/// inactive panel and cursor targets. This is the single place every UI
/// surface calls to run an action — surfaces never assemble file-operation
/// calls or resolve panels themselves.
///
/// A lightweight value: recreated per access via `AppState.commands`, holding
/// only a reference to its `AppState`.
@MainActor
package struct CommandRunner {

    package let appState: AppState

    private var active: PanelViewModel { appState.activePanelViewModel }
    private var inactive: PanelViewModel { appState.inactivePanelViewModel }

    // MARK: - Execution

    package func perform(_ command: Command) {
        switch command {
        case .goToParent:
            Task { await active.navigateToParent() }
        case .back:
            Task { await active.navigateBack() }
        case .forward:
            Task { await active.navigateForward() }
        case .goToPath:
            active.isPathBarEditing = true
        case .refresh:
            Task { await active.reload(.fresh) }

        case .open:
            Task { await active.openSelectedItem() }
        case .openItem(let item):
            Task { await active.openItem(item) }
        case .edit:
            active.openSelectedFileWithDefaultApp()
        case .quickLook:
            if let url = active.previewURLForQuickLook() {
                appState.quickLook.show(url: url)
            }

        case .selectAll:
            active.selectAll()
        case .deselectAll:
            active.deselectAllKeepingFocus()
        case .toggleHidden:
            Task { await active.toggleHiddenFiles() }

        case .copy:
            appState.fileOperations.requestCopy(from: active, to: inactive)
        case .move:
            appState.fileOperations.requestMove(from: active, to: inactive)
        case .newFolder:
            appState.fileOperations.requestNewFolder()
        case .trash:
            appState.fileOperations.requestDelete(from: active)
        case .permanentDelete:
            appState.fileOperations.requestPermanentDelete(from: active)
        case .rename(let item):
            guard !item.isParentDirectory else { return }
            appState.fileOperations.requestRename(item: item)

        case .copyPaths:
            appState.copySelectedPathsToPasteboard()
        case .revealInFinder:
            let urls = active.selectedNonParentURLs()
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    // MARK: - Enablement

    /// Whether a command is currently actionable in the active panel. UI
    /// surfaces use this to enable/disable their items.
    package func isEnabled(_ command: Command) -> Bool {
        switch command {
        case .copy, .move, .trash, .permanentDelete, .copyPaths, .revealInFinder:
            return hasSelection
        case .edit, .quickLook:
            return active.previewURLForQuickLook() != nil
        case .rename(let item):
            return !item.isParentDirectory
        case .openItem(let item):
            return !item.isParentDirectory
        case .back:
            return active.state.historyIndex > 0
        case .forward:
            return active.state.historyIndex < active.state.history.count - 1
        case .open, .goToParent, .goToPath, .refresh,
             .selectAll, .deselectAll, .toggleHidden, .newFolder:
            return true
        }
    }

    // MARK: - Target resolution

    /// The item a Rename should target given the current cursor — the single
    /// selected non-parent row, else the focused row. `nil` when nothing
    /// renameable is under the cursor.
    package var renameTarget: FileItem? {
        let cursor = active.state.cursor
        let targetID = cursor.selected.count == 1 ? cursor.selected.first : cursor.focused
        guard let targetID,
              let item = active.state.items.first(where: { $0.id == targetID }),
              !item.isParentDirectory else {
            return nil
        }
        return item
    }

    // MARK: - Private

    private var hasSelection: Bool {
        active.visibleItems.contains { item in
            active.state.cursor.selected.contains(item.id) && !item.isParentDirectory
        }
    }
}
