import SwiftUI
import Models
import Utilities
import Services
import ViewModels
import AppEnvironment

/// Root view: two side-by-side file panels with a resizable splitter,
/// a toolbar area, and a command bar at the bottom.
/// Handles global keyboard shortcuts that apply to the active panel.
package struct MainWindowView: View {

    @Environment(AppState.self) private var appState
    @FocusState private var focusedPanel: PanelSide?

    private var runner: CommandRunner { appState.commands }

    package var body: some View {
        @Bindable var ops = appState.fileOperations
        let dateFormat = appState.configuration.current.appearanceDateFormat
        let fontSize = CGFloat(appState.configuration.current.appearanceFontSize)

        mainContentLayer(showProgressOverlay: ops.showProgressOverlay, operations: ops.activeOperations)
            .environment(\.lcPanelDateFormat, dateFormat)
            .environment(\.lcPanelFontSize, fontSize)
            .task {
                async let leftLoad: Void = appState.leftPanel.reload(.fresh)
                async let rightLoad: Void = appState.rightPanel.reload(.fresh)
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
                    async let left: Void = appState.leftPanel.reload(.keepSelection)
                    async let right: Void = appState.rightPanel.reload(.keepSelection)
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
                onCmdL: { runner.perform(.goToPath) },
                onCmdDown: { runner.perform(.open) },
                onCmdShiftA: { runner.perform(.deselectAll) },
                onEscape: {
                    false
                },
                onSpace: {
                    guard !appState.activePanelViewModel.isPathBarEditing else {
                        return false
                    }
                    runner.perform(.quickLook)
                    return true
                },
                onHome: { appState.activePanelViewModel.focusFirstListItem() },
                onEnd: { appState.activePanelViewModel.focusLastListItem() },
                onF3: { runner.perform(.quickLook) },
                onF4: { runner.perform(.edit) },
                onF2: { if let item = runner.renameTarget { runner.perform(.rename(item)) } },
                onF5: { runner.perform(.copy) },
                onF6: { runner.perform(.move) },
                onF7: { runner.perform(.newFolder) },
                onF8: { runner.perform(.trash) },
                onDeleteKeyNavigateParent: { runner.perform(.goToParent) },
                onPermanentDelete: { runner.perform(.permanentDelete) },
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
                // Source-panel intent depends on the operation: delete / move
                // need to land on the neighbour of the doomed URLs; copy
                // (which doesn't remove rows from the source) keeps selection.
                let sourceIntent: Cursor.Intent
                switch ops.pendingOperationType {
                case .delete(let urls), .permanentDelete(let urls):
                    sourceIntent = .landOnNeighbourOf(urls)
                case .move(let urls, _):
                    sourceIntent = .landOnNeighbourOf(urls)
                default:
                    sourceIntent = .keepSelection
                }

                ops.confirmOperation(
                    reloadSource: { [weak appState] in
                        await appState?.activePanelViewModel.reload(sourceIntent)
                    },
                    reloadDestination: { [weak appState] in
                        await appState?.inactivePanelViewModel.reload(.keepSelection)
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

                    if folderName.isEmpty {
                        await panel.reload(.keepSelection)
                        await appState.inactivePanelViewModel.reload(.keepSelection)
                    } else {
                        let newFolderURL = dir.appendingPathComponent(folderName)
                        await panel.reload(.landOnNew(newFolderURL))
                        await appState.inactivePanelViewModel.reload(.keepSelection)
                        panel.highlight(url: newFolderURL)
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

                        let parentDir = item.url.deletingLastPathComponent()
                        let newURL = parentDir.appendingPathComponent(newName)
                        await panel.reload(.landOnNew(newURL))
                        await appState.inactivePanelViewModel.reload(.keepSelection)
                        panel.highlight(url: newURL)
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

    // MARK: - Actions

    private func handleReturn() {
        let panel = appState.activePanelViewModel

        // If exactly one non-parent, non-directory item is selected, rename it.
        // If a directory or parent is selected, navigate into it.
        let targetID: UUID? = if panel.state.cursor.selected.count == 1 {
            panel.state.cursor.selected.first
        } else {
            panel.state.cursor.focused
        }

        guard let targetID,
              let item = panel.state.items.first(where: { $0.id == targetID }) else {
            return
        }

        if item.isNavigableDirectory {
            runner.perform(.openItem(item))
        } else {
            // Rename on Enter for non-directory items (macOS convention)
            runner.perform(.rename(item))
        }
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

                CommandBarView(appState: appState)
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

    package let keyboardRoutingActive: Bool
    package let onTab: () -> Void
    package let onReturn: () -> Void
    package let onCmdL: () -> Void
    package let onCmdDown: () -> Void
    package let onCmdShiftA: () -> Void
    /// Returns true if handled
    package let onEscape: () -> Bool
    /// Returns true if key was consumed
    package let onSpace: () -> Bool
    package let onHome: () -> Void
    package let onEnd: () -> Void
    package let onF3: () -> Void
    package let onF4: () -> Void
    package let onF2: () -> Void
    package let onF5: () -> Void
    package let onF6: () -> Void
    package let onF7: () -> Void
    package let onF8: () -> Void
    /// Plain Delete / forward-delete — parent directory (not Trash).
    package let onDeleteKeyNavigateParent: () -> Void
    package let onPermanentDelete: () -> Void
    package let pathEditingBlocksDelete: () -> Bool
    package let typeAhead: (KeyPress) -> KeyPress.Result

    package func body(content: Content) -> some View {
        content
            .onKeyPress(.tab, phases: .down) { _ in
                guard keyboardRoutingActive else { return .ignored }
                onTab()
                return .handled
            }
            .onKeyPress(.return, phases: .down) { _ in
                // While a dialog (confirm / rename / new folder / conflict) is
                // up, let Return fall through to the dialog's default button
                // instead of swallowing it for panel navigation.
                guard keyboardRoutingActive else { return .ignored }
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
                onDeleteKeyNavigateParent()
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
                onDeleteKeyNavigateParent()
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

#Preview {
    MainWindowView()
        .environment(AppState())
}
