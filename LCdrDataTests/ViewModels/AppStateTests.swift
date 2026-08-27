import Testing
import Foundation
@testable import Services
@testable import ViewModels
@testable import Models

@MainActor
struct AppStateTests {

    @Test func defaultInitStartsWithLeftActive() {
        // Arrange & Act
        let state = AppState()

        // Assert
        #expect(state.activePanel == .left)
    }

    @Test func activePanelViewModelReturnsCorrectSide() {
        // Arrange
        let state = AppState()

        // Assert
        #expect(state.activePanelViewModel.side == .left)
        #expect(state.inactivePanelViewModel.side == .right)
    }

    @Test func switchActivePanelToggles() {
        // Arrange
        let state = AppState()
        #expect(state.activePanel == .left)

        // Act
        state.switchActivePanel()

        // Assert
        #expect(state.activePanel == .right)
        #expect(state.activePanelViewModel.side == .right)
        #expect(state.inactivePanelViewModel.side == .left)

        // Act again
        state.switchActivePanel()

        // Assert
        #expect(state.activePanel == .left)
    }

    @Test func customDirectories() {
        // Arrange & Act
        let left = URL(fileURLWithPath: "/Users/test/Documents")
        let right = URL(fileURLWithPath: "/Users/test/Downloads")
        let state = AppState(
            leftDirectory: left,
            rightDirectory: right
        )

        // Assert
        #expect(state.leftPanel.state.currentDirectory == left)
        #expect(state.rightPanel.state.currentDirectory == right)
    }

    // MARK: - editor settings

    private func makeConfiguration(
        editorBundleID: String,
        openFolders: Bool = false
    ) throws -> ConfigurationService {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataAppStateCfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let service = ConfigurationService(
            bundle: Bundle.main,
            fileManager: .default,
            configDirectory: tmp,
            defaultKDLTextOverride: """
            editor {
                default-app "\(editorBundleID)"
                open-folders #\(openFolders)
            }

            """
        )
        try service.load()
        return service
    }

    private func makeAppState(configuration: ConfigurationService) -> AppState {
        AppState(
            configuration: configuration,
            sandboxAccess: SandboxAccessService(
                presenter: NoopAccessPresenter(),
                bookmarkStore: BookmarkStore()
            )
        )
    }

    @Test func bothPanelsAreSeededWithTheConfiguredEditor() throws {
        // Arrange & Act
        let state = makeAppState(configuration: try makeConfiguration(editorBundleID: "com.foo.Bar"))

        // Assert
        #expect(state.leftPanel.editorDefaultAppBundleID == "com.foo.Bar")
        #expect(state.rightPanel.editorDefaultAppBundleID == "com.foo.Bar")
    }

    @Test func applyingConfigurationPushesTheNewEditorToBothPanels() async throws {
        // Arrange
        let configuration = try makeConfiguration(editorBundleID: "com.foo.Bar")
        let state = makeAppState(configuration: configuration)

        // Act
        try configuration.apply(fromUserKDL: """
        editor {
            default-app "com.other.Editor"
        }

        """)
        await state.applyEffectiveConfiguration()

        // Assert
        #expect(state.leftPanel.editorDefaultAppBundleID == "com.other.Editor")
        #expect(state.rightPanel.editorDefaultAppBundleID == "com.other.Editor")
    }

    @Test func bothPanelsAreSeededWithOpenFolders() throws {
        // Arrange & Act
        let state = makeAppState(
            configuration: try makeConfiguration(editorBundleID: "com.foo.Bar", openFolders: true)
        )

        // Assert
        #expect(state.leftPanel.editorOpenFolders == true)
        #expect(state.rightPanel.editorOpenFolders == true)
    }

    @Test func applyingConfigurationPushesOpenFoldersToBothPanels() async throws {
        // Arrange — starts off.
        let configuration = try makeConfiguration(editorBundleID: "com.foo.Bar")
        let state = makeAppState(configuration: configuration)
        #expect(state.leftPanel.editorOpenFolders == false)

        // Act
        try configuration.apply(fromUserKDL: """
        editor {
            open-folders #true
        }

        """)
        await state.applyEffectiveConfiguration()

        // Assert
        #expect(state.leftPanel.editorOpenFolders == true)
        #expect(state.rightPanel.editorOpenFolders == true)
    }
}
