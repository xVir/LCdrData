import AppKit
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

    @MainActor
    init(
        leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileOperationService: FileOperationServiceProtocol = FileOperationService(),
        configuration: ConfigurationService
    ) {
        self.configuration = configuration

        let cfg = configuration.current
        let sandboxAccess = SandboxAccessService()
        self.leftPanel = PanelViewModel(
            side: .left,
            initialDirectory: leftDirectory,
            sortDescriptor: cfg.sortDescriptor,
            showHiddenFiles: cfg.panelShowHiddenFiles,
            directoryWatchingEnabled: true,
            sandboxAccessService: sandboxAccess
        )
        self.rightPanel = PanelViewModel(
            side: .right,
            initialDirectory: rightDirectory,
            sortDescriptor: cfg.sortDescriptor,
            showHiddenFiles: cfg.panelShowHiddenFiles,
            directoryWatchingEnabled: true,
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
        fileOperationService: FileOperationServiceProtocol = FileOperationService()
    ) {
        let configuration = ConfigurationService()
        try? configuration.load()
        self.init(
            leftDirectory: leftDirectory,
            rightDirectory: rightDirectory,
            fileOperationService: fileOperationService,
            configuration: configuration
        )
    }

    /// Stops security-scoped access for both panels (call before exit).
    func releasePanelSecurityScope() {
        leftPanel.releaseDirectorySecurityScope()
        rightPanel.releaseDirectorySecurityScope()
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
        async let left: Void = leftPanel.reload(.keepSelection)
        async let right: Void = rightPanel.reload(.keepSelection)
        _ = await (left, right)
    }

    @MainActor
    func presentOpenFolderPanel() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = activePanelViewModel.state.currentDirectory
        panel.prompt = "Open"
        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return }
        await activePanelViewModel.navigate(to: url)
    }

    func copySelectedPathsToPasteboard() {
        let lines = activePanelViewModel.selectedNonParentURLs().map(\.path)
        guard !lines.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// Navigates the active panel to a configured favorite path (`~` expanded).
    @MainActor
    func navigateActivePanelToFavorite(path: String) async {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        await activePanelViewModel.navigate(to: url)
    }
}
