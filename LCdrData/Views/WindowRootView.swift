import SwiftUI
import Models
import Utilities
import Services
import ViewModels
import AppEnvironment

/// One per window. Owns the per-window `AppState`, publishes it as a focused
/// value for menu commands, captures bookmarks on panel navigation, and writes
/// fresh paths back into the `PanelSession` so macOS state-restoration sees them.
package struct WindowRootView: View {

    @Binding var session: PanelSession
    package let env: AppEnvironment

    @State private var appState: AppState
    @Environment(\.controlActiveState) private var controlActiveState

    package init(session: Binding<PanelSession>, env: AppEnvironment) {
        self._session = session
        self.env = env

        let leftURL = env.bookmarkStore.resolve(path: session.wrappedValue.leftPath)
            ?? URL(fileURLWithPath: session.wrappedValue.leftPath, isDirectory: true)
        let rightURL = env.bookmarkStore.resolve(path: session.wrappedValue.rightPath)
            ?? URL(fileURLWithPath: session.wrappedValue.rightPath, isDirectory: true)

        let state = AppState(
            leftDirectory: leftURL,
            rightDirectory: rightURL,
            configuration: env.configuration,
            sandboxAccess: env.sandboxAccess
        )
        state.leftPanel.state.location = session.wrappedValue.leftLocation ?? .directory(leftURL)
        state.rightPanel.state.location = session.wrappedValue.rightLocation ?? .directory(rightURL)
        _appState = State(initialValue: state)
        env.mostRecentAppState = state
    }

    package var body: some View {
        MainWindowView()
            .environment(appState)
            .focusedSceneValue(\.appState, appState)
            .task { await env.start() }
            .onChange(of: controlActiveState) { _, newValue in
                if newValue == .key {
                    env.mostRecentAppState = appState
                }
            }
            .onChange(of: appState.leftPanel.state.location) { _, newLocation in
                let persistentDirectory = newLocation.persistentDirectory
                env.bookmarkStore.save(url: persistentDirectory)
                session = PanelSession(
                    id: session.id,
                    leftPath: persistentDirectory.path,
                    rightPath: session.rightPath,
                    leftLocation: newLocation,
                    rightLocation: session.rightLocation
                )
            }
            .onChange(of: appState.rightPanel.state.location) { _, newLocation in
                let persistentDirectory = newLocation.persistentDirectory
                env.bookmarkStore.save(url: persistentDirectory)
                session = PanelSession(
                    id: session.id,
                    leftPath: session.leftPath,
                    rightPath: persistentDirectory.path,
                    leftLocation: session.leftLocation,
                    rightLocation: newLocation
                )
            }
            .onChange(of: session) { _, newValue in
                env.rememberLastSession(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .lcdrConfigurationApplied)) { _ in
                Task { await appState.applyEffectiveConfiguration() }
            }
    }
}
