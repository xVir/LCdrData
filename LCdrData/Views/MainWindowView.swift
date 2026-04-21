import SwiftUI

/// Root view: two side-by-side file panels with a resizable splitter,
/// a toolbar area, and a command bar at the bottom.
/// Handles global keyboard shortcuts that apply to the active panel.
struct MainWindowView: View {

    @Environment(AppState.self) private var appState
    @FocusState private var focusedPanel: PanelSide?

    var body: some View {
        @Bindable var ops = appState.fileOperations

        ZStack {
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
                CommandBarView(
                    hasSelection: hasSelection,
                    onCopy: { performCopy() },
                    onMove: { performMove() },
                    onMkdir: { performMkdir() },
                    onDelete: { performDelete() }
                )
            }
            .frame(minWidth: 800, minHeight: 500)

            // Progress overlay for long-running operations
            if ops.showProgressOverlay {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                FileOperationProgressView(
                    operations: ops.activeOperations,
                    onCancel: { ops.cancelCurrentOperation() }
                )
            }
        }
        .focusedSceneValue(\.activePanel, appState.activePanelViewModel)
        .task {
            // Load both panels on first appearance
            async let leftLoad: Void = appState.leftPanel.loadDirectory()
            async let rightLoad: Void = appState.rightPanel.loadDirectory()
            _ = await (leftLoad, rightLoad)
            // Set initial keyboard focus to the left panel
            focusedPanel = .left
        }
        // Refresh both panels when the app regains focus so that
        // external file system changes (files created in Terminal, etc.)
        // are reflected immediately.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                async let left: Void = appState.leftPanel.reloadKeepingSelection()
                async let right: Void = appState.rightPanel.reloadKeepingSelection()
                _ = await (left, right)
            }
        }
        // Sync focus state -> app state
        .onChange(of: focusedPanel) { _, newValue in
            if let newValue {
                appState.activePanel = newValue
            }
        }
        // Sync app state -> focus state (e.g. when clicking a panel)
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
            handleReturn()
            return .handled
        }
        // F5 — Copy
        .onKeyPress(KeyboardShortcuts.f5Key, phases: .down) { _ in
            performCopy()
            return .handled
        }
        // F6 — Move
        .onKeyPress(KeyboardShortcuts.f6Key, phases: .down) { _ in
            performMove()
            return .handled
        }
        // F7 — Mkdir
        .onKeyPress(KeyboardShortcuts.f7Key, phases: .down) { _ in
            performMkdir()
            return .handled
        }
        // F8 — Delete
        .onKeyPress(KeyboardShortcuts.f8Key, phases: .down) { _ in
            performDelete()
            return .handled
        }
        // Note: Backspace/Delete for "go to parent" is handled via
        // .onDeleteCommand on the List in FileTableView, because
        // SwiftUI's List intercepts .delete key events before they
        // can propagate to parent views.

        // MARK: - Confirmation Dialog
        .confirmationDialog(
            "Confirm Operation",
            isPresented: $ops.showConfirmationDialog,
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                ops.confirmOperation(
                    reloadSource: { [weak appState] in
                        await appState?.activePanelViewModel.reloadKeepingSelection()
                    },
                    reloadDestination: { [weak appState] in
                        await appState?.inactivePanelViewModel.reloadKeepingSelection()
                    }
                )
            }
            .keyboardShortcut(.defaultAction)

            Button("Cancel", role: .cancel) {
                ops.cancelConfirmation()
            }
        } message: {
            Text(ops.confirmationMessage)
        }

        // MARK: - Conflict Resolution Dialog
        .sheet(isPresented: $ops.showConflictDialog) {
            if let conflict = ops.currentConflict {
                ConflictResolutionView(conflict: conflict) { resolution, applyToAll in
                    ops.resolveCurrentConflict(with: resolution, applyToAll: applyToAll)
                }
            }
        }

        // MARK: - New Folder Dialog
        .alert("New Folder", isPresented: $ops.showNewFolderDialog) {
            TextField("Folder name", text: $ops.newFolderName)
            Button("Create") {
                Task {
                    await ops.performCreateFolder(
                        in: appState.activePanelViewModel.state.currentDirectory
                    )
                    await appState.activePanelViewModel.reloadKeepingSelection()
                    await appState.inactivePanelViewModel.reloadKeepingSelection()
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new folder:")
        }

        // MARK: - Rename Dialog
        .alert("Rename", isPresented: $ops.showRenameDialog) {
            TextField("New name", text: $ops.renameName)
            Button("Rename") {
                Task {
                    await ops.performRename()
                    await appState.activePanelViewModel.reloadKeepingSelection()
                    await appState.inactivePanelViewModel.reloadKeepingSelection()
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                ops.renameItem = nil
            }
        } message: {
            if let item = ops.renameItem {
                Text("Enter a new name for \"\(item.name)\":")
            }
        }

        // MARK: - Error Alert
        .alert("Error", isPresented: $ops.showErrorAlert) {
            Button("OK") {
                ops.errorMessage = nil
            }
        } message: {
            if let error = ops.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Computed Properties

    private var hasSelection: Bool {
        let panel = appState.activePanelViewModel
        return panel.state.items.contains { item in
            panel.state.selectedItemIDs.contains(item.id) && !item.isParentDirectory
        }
    }

    // MARK: - Actions

    private func handleReturn() {
        let panel = appState.activePanelViewModel
        let ops = appState.fileOperations

        // If exactly one non-parent, non-directory item is selected, rename it.
        // If a directory or parent is selected, navigate into it.
        let targetID: UUID? = if panel.state.selectedItemIDs.count == 1 {
            panel.state.selectedItemIDs.first
        } else {
            panel.state.focusedItemID
        }

        guard let targetID,
              let item = panel.state.items.first(where: { $0.id == targetID }) else {
            return
        }

        if item.isDirectory {
            Task { await panel.navigate(to: item.url) }
        } else {
            // Rename on Enter for non-directory items (macOS convention)
            ops.requestRename(item: item)
        }
    }

    private func performCopy() {
        appState.fileOperations.requestCopy(
            from: appState.activePanelViewModel,
            to: appState.inactivePanelViewModel
        )
    }

    private func performMove() {
        appState.fileOperations.requestMove(
            from: appState.activePanelViewModel,
            to: appState.inactivePanelViewModel
        )
    }

    private func performMkdir() {
        appState.fileOperations.requestNewFolder()
    }

    private func performDelete() {
        appState.fileOperations.requestDelete(
            from: appState.activePanelViewModel
        )
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
