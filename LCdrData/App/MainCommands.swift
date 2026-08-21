import SwiftUI
import Core
import Services
import ViewModels
import AppEnvironment
import Views

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

        CommandGroup(after: .appInfo) {
            Button("Grant Folder Access\u{2026}") {
                let suggested = focused?.activePanelViewModel.state.currentDirectory
                    ?? FileManager.default.homeDirectoryForCurrentUser
                Task {
                    _ = await env.sandboxAccess.requestAccessIfNeeded(
                        context: .manualGrant(suggestedURL: suggested)
                    )
                }
            }
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
            commandButton("Go to Parent Directory", .goToParent)
            commandButton("Refresh", .refresh)
            commandButton("Toggle Hidden Files", .toggleHidden)

            Divider()

            commandButton("Back", .back)
            commandButton("Forward", .forward)

            Divider()

            commandButton("Go to Path…", .goToPath)
            commandButton("Open", .open)
        }

        CommandGroup(after: .pasteboard) {
            commandButton("Copy Selected Paths", .copyPaths)

            Divider()

            commandButton("Select All", .selectAll)
            commandButton("Deselect All", .deselectAll)

            Divider()

            commandButton("Move to Trash…", .trash)
            commandButton("Delete Immediately…", .permanentDelete)
        }
    }

    /// A menu-bar button that runs a `Command` through the focused window's
    /// runner, with its shortcut sourced from `CommandCatalog`.
    @ViewBuilder
    private func commandButton(_ title: String, _ command: Command) -> some View {
        Button(title) {
            focused?.commands.perform(command)
        }
        .keyboardShortcut(CommandCatalog.shortcut(for: command))
        .disabled(focused == nil)
    }
}
