//
//  MainWindowView.swift
//  LCDR Data
//
//  Created by Dima Skachkov on 02.04.2026.
//

import SwiftUI

/// Root view: two side-by-side file panels with a resizable splitter,
/// a toolbar area, and a command bar at the bottom.
/// Handles global keyboard shortcuts that apply to the active panel.
struct MainWindowView: View {

    @Environment(AppState.self) private var appState
    @FocusState private var focusedPanel: PanelSide?

    var body: some View {
        VStack(spacing: 0) {
            // Dual-panel area with resizable splitter
            HSplitView {
                PanelView(viewModel: appState.leftPanel)
                    .focusSection()
                    .focused($focusedPanel, equals: .left)
                    .frame(minWidth: 300)

                PanelView(viewModel: appState.rightPanel)
                    .focusSection()
                    .focused($focusedPanel, equals: .right)
                    .frame(minWidth: 300)
            }

            Divider()

            // Command bar at the bottom
            CommandBarView()
        }
        .frame(minWidth: 800, minHeight: 500)
        .focusedSceneValue(\.activePanel, appState.activePanelViewModel)
        .task {
            // Load both panels on first appearance
            async let leftLoad: Void = appState.leftPanel.loadDirectory()
            async let rightLoad: Void = appState.rightPanel.loadDirectory()
            _ = await (leftLoad, rightLoad)
            // Set initial keyboard focus to the left panel
            focusedPanel = .left
        }
        // Sync focus state → app state
        .onChange(of: focusedPanel) { _, newValue in
            if let newValue {
                appState.activePanel = newValue
            }
        }
        // Sync app state → focus state (e.g. when clicking a panel)
        .onChange(of: appState.activePanel) { _, newValue in
            focusedPanel = newValue
        }
        // MARK: - Keyboard Shortcuts
        .onKeyPress(.tab, phases: .down) { _ in
            appState.switchActivePanel()
            focusedPanel = appState.activePanel
            return .handled
        }
        .onKeyPress(.return, phases: .down) { _ in
            Task {
                await appState.activePanelViewModel.openSelectedItem()
            }
            return .handled
        }
        // Note: Backspace/Delete for "go to parent" is handled via
        // .onDeleteCommand on the List in FileTableView, because
        // SwiftUI's List intercepts .delete key events before they
        // can propagate to parent views.
    }
}

// MARK: - Focused Scene Value for Active Panel

struct ActivePanelKey: FocusedValueKey {
    typealias Value = PanelViewModel
}

extension FocusedValues {
    var activePanel: PanelViewModel? {
        get { self[ActivePanelKey.self] }
        set { self[ActivePanelKey.self] = newValue }
    }
}

#Preview {
    MainWindowView()
        .environment(AppState())
}
