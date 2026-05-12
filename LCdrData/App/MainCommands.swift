import SwiftUI

/// Menu commands that target the currently focused window's `AppState` via
/// `@FocusedValue(\.appState)`. When no window has focus (e.g. Settings is
/// frontmost), the navigation/selection commands are disabled. The Favorites
/// menu reads directly from the shared configuration so it stays usable.
struct MainCommands: Commands {

    let env: AppEnvironment
    @FocusedValue(\.appState) private var focused: AppState?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                guard let focused else { return }
                Task { await focused.presentOpenFolderPanel() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(focused == nil)
        }

        CommandMenu("Favorites") {
            let entries = env.configuration.current.bookmarkEntries
            if entries.isEmpty {
                Button("No favorites — add in Settings") {}
                    .disabled(true)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Button(entry.label) {
                        guard let focused else { return }
                        Task { await focused.navigateActivePanelToFavorite(path: entry.path) }
                    }
                    .disabled(focused == nil)
                }
            }
        }

        CommandGroup(after: .sidebar) {
            Button("Go to Parent Directory") {
                guard let focused else { return }
                Task { await focused.activePanelViewModel.navigateToParent() }
            }
            .keyboardShortcut(KeyboardShortcuts.goToParent)
            .disabled(focused == nil)

            Button("Refresh") {
                guard let focused else { return }
                Task { await focused.activePanelViewModel.reload(.fresh) }
            }
            .keyboardShortcut(KeyboardShortcuts.refresh)
            .disabled(focused == nil)

            Button("Toggle Hidden Files") {
                guard let focused else { return }
                Task { await focused.activePanelViewModel.toggleHiddenFiles() }
            }
            .keyboardShortcut(KeyboardShortcuts.toggleHidden)
            .disabled(focused == nil)

            Divider()

            Button("Back") {
                guard let focused else { return }
                Task { await focused.activePanelViewModel.navigateBack() }
            }
            .keyboardShortcut(KeyboardShortcuts.historyBack)
            .disabled(focused == nil)

            Button("Forward") {
                guard let focused else { return }
                Task { await focused.activePanelViewModel.navigateForward() }
            }
            .keyboardShortcut(KeyboardShortcuts.historyForward)
            .disabled(focused == nil)

            Divider()

            Button("Go to Path…") {
                guard let focused else { return }
                focused.activePanelViewModel.isPathBarEditing = true
            }
            .keyboardShortcut(KeyboardShortcuts.goToPath)
            .disabled(focused == nil)

            Button("Open") {
                guard let focused else { return }
                Task { await focused.activePanelViewModel.openSelectedItem() }
            }
            .keyboardShortcut(KeyboardShortcuts.openItem)
            .disabled(focused == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy Selected Paths") {
                focused?.copySelectedPathsToPasteboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(focused == nil)

            Divider()

            Button("Select All") {
                focused?.activePanelViewModel.selectAll()
            }
            .keyboardShortcut(KeyboardShortcuts.selectAll)
            .disabled(focused == nil)

            Button("Deselect All") {
                focused?.activePanelViewModel.deselectAllKeepingFocus()
            }
            .keyboardShortcut(KeyboardShortcuts.deselectAll)
            .disabled(focused == nil)

            Divider()

            Button("Move to Trash…") {
                guard let focused else { return }
                focused.fileOperations.requestDelete(from: focused.activePanelViewModel)
            }
            .disabled(focused == nil)

            Button("Delete Immediately…") {
                guard let focused else { return }
                focused.fileOperations.requestPermanentDelete(from: focused.activePanelViewModel)
            }
            .keyboardShortcut(KeyboardShortcuts.permanentDelete)
            .disabled(focused == nil)
        }
    }
}
