import SwiftUI

@main
struct LCdrDataApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appState)
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            // Merge into the system File / Edit / View menus — do not use CommandMenu("File") etc.,
            // or macOS shows duplicate menu titles.

            CommandGroup(after: .newItem) {
                Button("Open Folder…") {
                    Task { await appState.presentOpenFolderPanel() }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Favorites") {
                let entries = appState.configuration.current.bookmarkEntries
                if entries.isEmpty {
                    Button("No favorites — add in Settings") {}
                        .disabled(true)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        Button(entry.label) {
                            Task {
                                await appState.navigateActivePanelToFavorite(path: entry.path)
                            }
                        }
                    }
                }
            }

            // Navigation commands
            CommandGroup(after: .sidebar) {
                Button("Go to Parent Directory") {
                    Task {
                        await appState.activePanelViewModel.navigateToParent()
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.goToParent)

                Button("Refresh") {
                    Task {
                        await appState.activePanelViewModel.reload(.fresh)
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.refresh)

                Button("Toggle Hidden Files") {
                    Task {
                        await appState.activePanelViewModel.toggleHiddenFiles()
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.toggleHidden)

                Divider()

                Button("Back") {
                    Task {
                        await appState.activePanelViewModel.navigateBack()
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.historyBack)

                Button("Forward") {
                    Task {
                        await appState.activePanelViewModel.navigateForward()
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.historyForward)

                Divider()

                Button("Go to Path…") {
                    appState.activePanelViewModel.isPathBarEditing = true
                }
                .keyboardShortcut(KeyboardShortcuts.goToPath)

                Button("Open") {
                    Task {
                        await appState.activePanelViewModel.openSelectedItem()
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.openItem)
            }

            // Selection commands (Edit menu, after Cut/Copy/Paste)
            CommandGroup(after: .pasteboard) {
                Button("Copy Selected Paths") {
                    appState.copySelectedPathsToPasteboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Divider()

                Button("Select All") {
                    appState.activePanelViewModel.selectAll()
                }
                .keyboardShortcut(KeyboardShortcuts.selectAll)

                Button("Deselect All") {
                    appState.activePanelViewModel.deselectAllKeepingFocus()
                }
                .keyboardShortcut(KeyboardShortcuts.deselectAll)

                Divider()

                Button("Move to Trash…") {
                    appState.fileOperations.requestDelete(from: appState.activePanelViewModel)
                }

                Button("Delete Immediately…") {
                    appState.fileOperations.requestPermanentDelete(from: appState.activePanelViewModel)
                }
                .keyboardShortcut(KeyboardShortcuts.permanentDelete)
            }
        }

        Settings {
            ConfigurationView()
                .environment(appState)
        }
    }
}
