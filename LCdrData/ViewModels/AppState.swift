import Foundation
import Observation

/// Global application state holding both panels and tracking which is active.
@Observable
final class AppState {

    var leftPanel: PanelViewModel
    var rightPanel: PanelViewModel
    var activePanel: PanelSide
    var fileOperations: FileOperationViewModel
    let configuration: ConfigurationService

    private let panelPathStore: PanelPathStoreProtocol

    @MainActor
    init(
        leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileOperationService: FileOperationServiceProtocol = FileOperationService(),
        panelPathStore: PanelPathStoreProtocol = PanelPathStore(),
        configuration: ConfigurationService
    ) {
        self.panelPathStore = panelPathStore
        self.configuration = configuration
        try? configuration.load()

        let cfg = configuration.current

        // Restore saved paths if they still exist, otherwise use the
        // supplied defaults (home directory).
        let restored = panelPathStore.restore()
        let leftDir = restored?.left ?? leftDirectory
        let rightDir = restored?.right ?? rightDirectory

        let sandboxAccess = SandboxAccessService()
        self.leftPanel = PanelViewModel(
            side: .left,
            initialDirectory: leftDir,
            sortDescriptor: cfg.sortDescriptor,
            showHiddenFiles: cfg.panelShowHiddenFiles,
            sandboxAccessService: sandboxAccess
        )
        self.rightPanel = PanelViewModel(
            side: .right,
            initialDirectory: rightDir,
            sortDescriptor: cfg.sortDescriptor,
            showHiddenFiles: cfg.panelShowHiddenFiles,
            sandboxAccessService: sandboxAccess
        )
        self.activePanel = .left
        self.fileOperations = FileOperationViewModel(
            operationService: fileOperationService
        )
    }

    /// Convenience initializer with a default `ConfigurationService` (must run on the main actor).
    @MainActor
    convenience init(
        leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileOperationService: FileOperationServiceProtocol = FileOperationService(),
        panelPathStore: PanelPathStoreProtocol = PanelPathStore()
    ) {
        self.init(
            leftDirectory: leftDirectory,
            rightDirectory: rightDirectory,
            fileOperationService: fileOperationService,
            panelPathStore: panelPathStore,
            configuration: ConfigurationService()
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

    /// Re-applies `configuration.current` to both panels (sort, hidden files) and reloads listings.
    func applyEffectiveConfiguration() async {
        let cfg = configuration.current
        leftPanel.state.sortDescriptor = cfg.sortDescriptor
        rightPanel.state.sortDescriptor = cfg.sortDescriptor
        leftPanel.state.showHiddenFiles = cfg.panelShowHiddenFiles
        rightPanel.state.showHiddenFiles = cfg.panelShowHiddenFiles
        async let left: Void = leftPanel.reloadKeepingSelection()
        async let right: Void = rightPanel.reloadKeepingSelection()
        _ = await (left, right)
    }
}
