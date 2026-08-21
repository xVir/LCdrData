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
}
