//
//  AppState.swift
//  LCDR Data
//
//  Created by Dima Skachkov on 02.04.2026.
//

import Foundation
import Observation

/// Global application state holding both panels and tracking which is active.
@Observable
final class AppState {

    var leftPanel: PanelViewModel
    var rightPanel: PanelViewModel
    var activePanel: PanelSide

    init(
        leftDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rightDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let sandboxAccess = SandboxAccessService()
        self.leftPanel = PanelViewModel(
            side: .left,
            initialDirectory: leftDirectory,
            sandboxAccessService: sandboxAccess
        )
        self.rightPanel = PanelViewModel(
            side: .right,
            initialDirectory: rightDirectory,
            sandboxAccessService: sandboxAccess
        )
        self.activePanel = .left
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
