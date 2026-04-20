import SwiftUI

@main
struct LCdrDataApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(appState)
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
            }
        }
    }
}
