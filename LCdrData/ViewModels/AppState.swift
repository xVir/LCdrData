import Foundation
import Observation

/// Global application state holding both panels and tracking which is active.
@Observable
final class AppState {

    var leftPanel: PanelViewModel
    var rightPanel: PanelViewModel
    var activePanel: PanelSide
    var fileOperations: FileOperationViewModel

    private let panelPathStore: PanelPathStoreProtocol

    init(
        leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileOperationService: FileOperationServiceProtocol = FileOperationService(),
        panelPathStore: PanelPathStoreProtocol = PanelPathStore()
    ) {
        self.panelPathStore = panelPathStore

        // Restore saved paths if they still exist, otherwise use the
        // supplied defaults (home directory).
        let restored = panelPathStore.restore()
        let leftDir = restored?.left ?? leftDirectory
        let rightDir = restored?.right ?? rightDirectory

        let sandboxAccess = SandboxAccessService()
        self.leftPanel = PanelViewModel(
            side: .left,
            initialDirectory: leftDir,
            sandboxAccessService: sandboxAccess
        )
        self.rightPanel = PanelViewModel(
            side: .right,
            initialDirectory: rightDir,
            sandboxAccessService: sandboxAccess
        )
        self.activePanel = .left
        self.fileOperations = FileOperationViewModel(
            operationService: fileOperationService
        )
    }

    /// Persists the current panel directories so they can be restored on
    /// the next launch.
    func savePanelPaths() {
        panelPathStore.save(
            leftPath: leftPanel.state.currentDirectory.path,
            rightPath: rightPanel.state.currentDirectory.path
        )
    }

    /// Returns the currently active panel view model.
    var activePanelViewModel: PanelViewModel {
        activePanel == .left ? leftPanel : rightPanel
    }

    /// Returns the inactive (target) panel view model.
    var inactivePanelViewModel: PanelViewModel {
        activePanel == .left ? rightPanel : leftPanel
    }

    /// Switches the active panel to the other side.
    func switchActivePanel() {
        activePanel = (activePanel == .left) ? .right : .left
    }
}
