import SwiftUI

/// Root view: two side-by-side file panels with a resizable splitter,
/// a toolbar area, and a command bar at the bottom.
/// Handles global keyboard shortcuts that apply to the active panel.
struct MainWindowView: View {

    @Environment(AppState.self) private var appState
    @FocusState private var focusedPanel: PanelSide?
    @State private var quickLookController = QuickLookPreviewController()

    var body: some View {
        @Bindable var ops = appState.fileOperations
        let dateFormat = appState.configuration.current.appearanceDateFormat
        let fontSize = CGFloat(appState.configuration.current.appearanceFontSize)

        mainContentLayer(showProgressOverlay: ops.showProgressOverlay, operations: ops.activeOperations)
            .environment(\.lcPanelDateFormat, dateFormat)
            .environment(\.lcPanelFontSize, fontSize)
            .focusedSceneValue(\.activePanel, appState.activePanelViewModel)
            .task {
                async let leftLoad: Void = appState.leftPanel.loadDirectory()
                async let rightLoad: Void = appState.rightPanel.loadDirectory()
                _ = await (leftLoad, rightLoad)
                focusedPanel = .left
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard !appState.fileOperations.showConfirmationDialog
                        && !appState.fileOperations.showProgressOverlay
                        && appState.fileOperations.activeOperations.isEmpty else {
                    return
                }
                Task {
                    async let left: Void = appState.leftPanel.reloadKeepingSelection()
                    async let right: Void = appState.rightPanel.reloadKeepingSelection()
                    _ = await (left, right)
                }
            }
            .onChange(of: focusedPanel) { _, newValue in
                if let newValue {
                    appState.activePanel = newValue
                }
            }
            .onChange(of: appState.activePanel) { _, newValue in
                focusedPanel = newValue
            }
            .modifier(KeyShortcutModifier(
                keyboardRoutingActive: keyboardRoutingActive,
                onTab: {
                    appState.switchActivePanel()
                    focusedPanel = appState.activePanel
                },
                onReturn: { handleReturn() },
                onCmdL: { appState.activePanelViewModel.isPathBarEditing = true },
                onCmdDown: { Task { await appState.activePanelViewModel.openSelectedItem() } },
                onCmdShiftA: { appState.activePanelViewModel.deselectAllKeepingFocus() },
                onEscape: {
                    false
                },
                onSpace: {
                    let panel = appState.activePanelViewModel
                    guard !panel.isPathBarEditing else {
                        return false
                    }
                    panel.commanderSpaceSelect()
                    return true
                },
                onHome: { appState.activePanelViewModel.focusFirstListItem() },
                onEnd: { appState.activePanelViewModel.focusLastListItem() },
                onF3: { performQuickLook() },
                onF4: { performEditFile() },
                onF2: { performRename() },
                onF5: { performCopy() },
                onF6: { performMove() },
                onF7: { performMkdir() },
                onF8: { performDelete() },
                onDelete: { performDelete() },
                onPermanentDelete: { performPermanentDelete() },
                pathEditingBlocksDelete: {
                    appState.activePanelViewModel.isPathBarEditing
                },
                typeAhead: { handleTypeAheadKeyPress($0) }
            ))
            // MARK: - Confirmation Dialog
            .confirmationDialog(
            "Confirm Operation",
            isPresented: $ops.showConfirmationDialog,
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                // For delete and move operations, pre-compute which
                // neighbouring item should receive focus after the
                // selected items are removed from the source panel.
                switch ops.pendingOperationType {
                case .delete, .permanentDelete:
                    appState.activePanelViewModel.prepareForDeletion()
                case .move:
                    appState.activePanelViewModel.prepareForDeletion()
                default:
                    break
                }

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
                    let panel = appState.activePanelViewModel
                    let dir = panel.state.currentDirectory
                    let folderName = ops.newFolderName
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    await ops.performCreateFolder(in: dir)
                    await panel.reloadKeepingSelection()
                    await appState.inactivePanelViewModel.reloadKeepingSelection()

                    // Highlight the newly created folder and select it.
                    if !folderName.isEmpty {
                        let newFolderURL = dir.appendingPathComponent(folderName)
                        let newItem = FileItem(
                            url: newFolderURL, name: folderName, isDirectory: true
                        )
                        panel.state.selectedItemIDs = [newItem.id]
                        panel.state.focusedItemID = newItem.id
                        panel.highlightItem(id: newItem.id)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new folder:")
        }

        // MARK: - Rename Dialog
        .sheet(isPresented: $ops.showRenameDialog) {
            if let item = ops.renameItem {
                RenameDialogView(item: item) { newName in
                    Task {
                        let panel = appState.activePanelViewModel
                        await ops.performRename(newName: newName)
                        await panel.reloadKeepingSelection()
                        await appState.inactivePanelViewModel.reloadKeepingSelection()

                        // Select and highlight the renamed item.
                        let parentDir = item.url.deletingLastPathComponent()
                        let newURL = parentDir.appendingPathComponent(newName)
                        let newItem = FileItem(
                            url: newURL,
                            name: newName,
                            isDirectory: item.isDirectory
                        )
                        panel.state.selectedItemIDs = [newItem.id]
                        panel.state.focusedItemID = newItem.id
                        panel.highlightItem(id: newItem.id)
                    }
                }
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

    private var keyboardRoutingActive: Bool {
        let ops = appState.fileOperations
        return !ops.showConfirmationDialog
            && !ops.showProgressOverlay
            && !ops.showRenameDialog
            && !ops.showNewFolderDialog
            && !ops.showConflictDialog
    }

    private var hasSelection: Bool {
        let panel = appState.activePanelViewModel
        return panel.visibleItems.contains { item in
            panel.state.selectedItemIDs.contains(item.id) && !item.isParentDirectory
        }
    }

    private var canViewOrEditFile: Bool {
        appState.activePanelViewModel.previewURLForQuickLook() != nil
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

    private func performPermanentDelete() {
        appState.fileOperations.requestPermanentDelete(
            from: appState.activePanelViewModel
        )
    }

    private func performQuickLook() {
        guard let url = appState.activePanelViewModel.previewURLForQuickLook() else { return }
        quickLookController.show(url: url)
    }

    private func performEditFile() {
        appState.activePanelViewModel.openSelectedFileWithDefaultApp()
    }

    private func handleTypeAheadKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard keyboardRoutingActive else { return .ignored }
        let panel = appState.activePanelViewModel
        guard !panel.isPathBarEditing else { return .ignored }

        if press.modifiers.contains(.command)
            || press.modifiers.contains(.control)
            || press.modifiers.contains(.option) {
            return .ignored
        }

        let chars = press.characters
        guard chars.count == 1, let scalar = chars.unicodeScalars.first else {
            return .ignored
        }
        if scalar.value < 32 || scalar.value == 127 {
            return .ignored
        }

        if panel.handleTypeAheadInsert(String(chars)) {
            return .handled
        }
        return .ignored
    }

    private func performRename() {
        let panel = appState.activePanelViewModel

        let targetID: UUID? = if panel.state.selectedItemIDs.count == 1 {
            panel.state.selectedItemIDs.first
        } else {
            panel.state.focusedItemID
        }

        guard let targetID,
              let item = panel.state.items.first(where: { $0.id == targetID }),
              !item.isParentDirectory else {
            return
        }

        appState.fileOperations.requestRename(item: item)
    }

    @ViewBuilder
    private func mainContentLayer(showProgressOverlay: Bool, operations: [FileOperation]) -> some View {
        ZStack {
            VStack(spacing: 0) {
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

                CommandBarView(
                    canViewOrEditFile: canViewOrEditFile,
                    hasSelection: hasSelection,
                    onView: { performQuickLook() },
                    onEdit: { performEditFile() },
                    onCopy: { performCopy() },
                    onMove: { performMove() },
                    onMkdir: { performMkdir() },
                    onDelete: { performDelete() }
                )
            }
            .frame(minWidth: 800, minHeight: 500)

            if showProgressOverlay {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                FileOperationProgressView(
                    operations: operations,
                    onCancel: { appState.fileOperations.cancelCurrentOperation() }
                )
            }
        }
    }
}

// MARK: - Keyboard shortcut modifier (split out for faster type-checking)

private struct KeyShortcutModifier: ViewModifier {

    let keyboardRoutingActive: Bool
    let onTab: () -> Void
    let onReturn: () -> Void
    let onCmdL: () -> Void
    let onCmdDown: () -> Void
    let onCmdShiftA: () -> Void
    /// Returns true if handled
    let onEscape: () -> Bool
    /// Returns true if key was consumed
    let onSpace: () -> Bool
    let onHome: () -> Void
    let onEnd: () -> Void
    let onF3: () -> Void
    let onF4: () -> Void
    let onF2: () -> Void
    let onF5: () -> Void
    let onF6: () -> Void
    let onF7: () -> Void
    let onF8: () -> Void
    let onDelete: () -> Void
    let onPermanentDelete: () -> Void
    let pathEditingBlocksDelete: () -> Bool
    let typeAhead: (KeyPress) -> KeyPress.Result

    func body(content: Content) -> some View {
        content
            .onKeyPress(.tab, phases: .down) { _ in
                onTab()
                return .handled
            }
            .onKeyPress(.return, phases: .down) { _ in
                onReturn()
                return .handled
            }
            .onKeyPress(.escape, phases: .down) { _ in
                if onEscape() { return .handled }
                return .ignored
            }
            .onKeyPress(.space, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                return onSpace() ? .handled : .ignored
            }
            .onKeyPress(.home, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onHome()
                return .handled
            }
            .onKeyPress(.end, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onEnd()
                return .handled
            }
            .onKeyPress(KeyboardShortcuts.f3Key, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onF3()
                return .handled
            }
            .onKeyPress(KeyboardShortcuts.f4Key, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onF4()
                return .handled
            }
            .onKeyPress(KeyboardShortcuts.f2Key, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onF2()
                return .handled
            }
            .onKeyPress(KeyboardShortcuts.f5Key, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onF5()
                return .handled
            }
            .onKeyPress(KeyboardShortcuts.f6Key, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onF6()
                return .handled
            }
            .onKeyPress(KeyboardShortcuts.f7Key, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onF7()
                return .handled
            }
            .onKeyPress(KeyboardShortcuts.f8Key, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onF8()
                return .handled
            }
            .onKeyPress(.delete, phases: .down) { press in
                guard keyboardRoutingActive else { return .ignored }
                if press.modifiers.contains(.command) {
                    guard !pathEditingBlocksDelete() else { return .ignored }
                    onPermanentDelete()
                    return .handled
                }
                guard !pathEditingBlocksDelete() else { return .ignored }
                onDelete()
                return .handled
            }
            .onKeyPress(.deleteForward, phases: .down) { press in
                guard keyboardRoutingActive else { return .ignored }
                if press.modifiers.contains(.command) {
                    guard !pathEditingBlocksDelete() else { return .ignored }
                    onPermanentDelete()
                    return .handled
                }
                guard !pathEditingBlocksDelete() else { return .ignored }
                onDelete()
                return .handled
            }
            .onKeyPress(phases: .down) { press in
                let r = Self.handleCommandArrowsAndLetters(
                    press: press,
                    keyboardRoutingActive: keyboardRoutingActive,
                    onCmdL: onCmdL,
                    onCmdDown: onCmdDown,
                    onCmdShiftA: onCmdShiftA
                )
                if r != .ignored { return r }
                return typeAhead(press)
            }
    }

    private static func handleCommandArrowsAndLetters(
        press: KeyPress,
        keyboardRoutingActive: Bool,
        onCmdL: () -> Void,
        onCmdDown: () -> Void,
        onCmdShiftA: () -> Void
    ) -> KeyPress.Result {
        guard keyboardRoutingActive else { return .ignored }
        let cmd = press.modifiers.contains(.command)
        let shift = press.modifiers.contains(.shift)

        if press.key == KeyEquivalent("l"), cmd, !shift {
            onCmdL()
            return .handled
        }
        if press.key == .downArrow, cmd {
            onCmdDown()
            return .handled
        }
        if press.key == KeyEquivalent("a"), cmd, shift {
            onCmdShiftA()
            return .handled
        }
        return .ignored
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
