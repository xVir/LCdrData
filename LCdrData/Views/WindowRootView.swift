import SwiftUI

/// One per window. Owns the per-window `AppState`, publishes it as a focused
/// value for menu commands, captures bookmarks on panel navigation, and writes
/// fresh paths back into the `PanelSession` so macOS state-restoration sees them.
struct WindowRootView: View {

    @Binding var session: PanelSession
    let env: AppEnvironment

    @State private var appState: AppState
    @Environment(\.controlActiveState) private var controlActiveState

    init(session: Binding<PanelSession>, env: AppEnvironment) {
        self._session = session
        self.env = env

        let leftURL = env.bookmarkStore.resolve(path: session.wrappedValue.leftPath)
            ?? URL(fileURLWithPath: session.wrappedValue.leftPath, isDirectory: true)
        let rightURL = env.bookmarkStore.resolve(path: session.wrappedValue.rightPath)
            ?? URL(fileURLWithPath: session.wrappedValue.rightPath, isDirectory: true)

        let state = AppState(
            leftDirectory: leftURL,
            rightDirectory: rightURL,
            configuration: env.configuration
        )
        _appState = State(initialValue: state)
        env.mostRecentAppState = state
    }

    var body: some View {
        MainWindowView()
            .environment(appState)
            .focusedSceneValue(\.appState, appState)
            .onChange(of: controlActiveState) { _, newValue in
                if newValue == .key {
                    env.mostRecentAppState = appState
                }
            }
            .onChange(of: appState.leftPanel.state.currentDirectory) { _, newURL in
                env.bookmarkStore.save(url: newURL)
                session = PanelSession(
                    id: session.id,
                    leftPath: newURL.path,
                    rightPath: session.rightPath
                )
            }
            .onChange(of: appState.rightPanel.state.currentDirectory) { _, newURL in
                env.bookmarkStore.save(url: newURL)
                session = PanelSession(
                    id: session.id,
                    leftPath: session.leftPath,
                    rightPath: newURL.path
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .lcdrConfigurationApplied)) { _ in
                Task { await appState.applyEffectiveConfiguration() }
            }
    }
}
