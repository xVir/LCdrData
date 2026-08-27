import AppKit
import Foundation
import Observation
import Utilities
import Services
import Models

/// Global application state holding both panels and tracking which is active.
@Observable
package final class AppState {

    package var leftPanel: PanelViewModel
    package var rightPanel: PanelViewModel
    package var activePanel: PanelSide
    package var fileOperations: FileOperationViewModel
    package let configuration: ConfigurationService
    private let pathExpander: TildePathExpander

    /// Presents the system Quick Look panel. Owned per-window here (rather than
    /// as view `@State`) so `CommandRunner` can drive it.
    package let quickLook = QuickLookPreviewController()

    /// The single entry point every UI surface uses to run user actions.
    /// A lightweight value recreated on access — no retain cycle with `self`.
    package var commands: CommandRunner { CommandRunner(appState: self) }

    @MainActor
    package init(
        leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileOperationService: FileOperationServiceProtocol = FileOperationService(),
        archiveService: ArchiveServiceProtocol = ArchiveService(),
        configuration: ConfigurationService,
        sandboxAccess: SandboxAccessService,
        pathExpander: TildePathExpander = TildePathExpander()
    ) {
        self.configuration = configuration
        self.pathExpander = pathExpander

        let cfg = configuration.current
        self.leftPanel = PanelViewModel(
            side: .left,
            initialDirectory: leftDirectory,
            sortDescriptor: cfg.sortDescriptor,
            showHiddenFiles: cfg.panelShowHiddenFiles,
            editorDefaultAppBundleID: cfg.editorDefaultAppBundleID,
            editorOpenFolders: cfg.editorOpenFolders,
            directoryWatchingEnabled: true,
            archiveService: archiveService,
            sandboxAccessService: sandboxAccess
        )
        self.rightPanel = PanelViewModel(
            side: .right,
            initialDirectory: rightDirectory,
            sortDescriptor: cfg.sortDescriptor,
            showHiddenFiles: cfg.panelShowHiddenFiles,
            editorDefaultAppBundleID: cfg.editorDefaultAppBundleID,
            editorOpenFolders: cfg.editorOpenFolders,
            directoryWatchingEnabled: true,
            archiveService: archiveService,
            sandboxAccessService: sandboxAccess
        )
        self.activePanel = .left
        self.fileOperations = FileOperationViewModel(
            operationService: fileOperationService,
            browseOperationService: BrowseOperationService(
                fileService: fileOperationService,
                archiveService: archiveService
            )
        )
    }

    /// Convenience initializer with a default `ConfigurationService` (must run on the main actor).
    @MainActor
    package convenience init(
        leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileOperationService: FileOperationServiceProtocol = FileOperationService(),
        archiveService: ArchiveServiceProtocol = ArchiveService()
    ) {
        let configuration = ConfigurationService()
        try? configuration.load()
        let sandboxAccess = SandboxAccessService(
            presenter: NSOpenPanelAccessPresenter(),
            bookmarkStore: BookmarkStore()
        )
        self.init(
            leftDirectory: leftDirectory,
            rightDirectory: rightDirectory,
            fileOperationService: fileOperationService,
            archiveService: archiveService,
            configuration: configuration,
            sandboxAccess: sandboxAccess
        )
    }

    /// Stops security-scoped access for both panels (call before exit).
    package func releasePanelSecurityScope() {
        leftPanel.releaseDirectorySecurityScope()
        rightPanel.releaseDirectorySecurityScope()
    }

    /// Returns the currently active panel view model.
    package var activePanelViewModel: PanelViewModel {
        activePanel == .left ? leftPanel : rightPanel
    }

    /// Returns the inactive (target) panel view model.
    package var inactivePanelViewModel: PanelViewModel {
        activePanel == .left ? rightPanel : leftPanel
    }

    /// Switches the active panel to the other side.
    package func switchActivePanel() {
        activePanel = (activePanel == .left) ? .right : .left
    }

    /// Re-applies `configuration.current` to both panels (sort, hidden files) and reloads listings.
    package func applyEffectiveConfiguration() async {
        let cfg = configuration.current
        leftPanel.state.sortDescriptor = cfg.sortDescriptor
        rightPanel.state.sortDescriptor = cfg.sortDescriptor
        leftPanel.state.showHiddenFiles = cfg.panelShowHiddenFiles
        rightPanel.state.showHiddenFiles = cfg.panelShowHiddenFiles
        leftPanel.editorDefaultAppBundleID = cfg.editorDefaultAppBundleID
        rightPanel.editorDefaultAppBundleID = cfg.editorDefaultAppBundleID
        leftPanel.editorOpenFolders = cfg.editorOpenFolders
        rightPanel.editorOpenFolders = cfg.editorOpenFolders
        async let left: Void = leftPanel.reload(.keepSelection)
        async let right: Void = rightPanel.reload(.keepSelection)
        _ = await (left, right)
    }

    @MainActor
    package func presentOpenFolderPanel() async {
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

    package func copySelectedPathsToPasteboard() {
        let lines = activePanelViewModel.selectedNonParentURLs().map(\.path)
        guard !lines.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// Navigates the active panel to a configured favorite path (`~` expanded
    /// against the user's real home, not the sandbox container).
    @MainActor
    package func navigateActivePanelToFavorite(path: String) async {
        await activePanelViewModel.navigate(to: pathExpander.expand(path))
    }
}
