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
                        await appState.activePanelViewModel.loadDirectory()
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.refresh)

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

            // View commands
            CommandGroup(after: .toolbar) {
                Button("Toggle Hidden Files") {
                    Task {
                        await appState.activePanelViewModel.toggleHiddenFiles()
                    }
                }
                .keyboardShortcut(KeyboardShortcuts.toggleHidden)
            }

            // Selection commands
            CommandGroup(after: .pasteboard) {
                Button("Select All") {
                    appState.activePanelViewModel.selectAll()
                }
                .keyboardShortcut(KeyboardShortcuts.selectAll)

                Button("Deselect All") {
                    appState.activePanelViewModel.deselectAllKeepingFocus()
                }
                .keyboardShortcut(KeyboardShortcuts.deselectAll)

                Divider()

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
