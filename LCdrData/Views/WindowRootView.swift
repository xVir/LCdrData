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
        state.leftPanel.restoreTabs(
            from: session.wrappedValue.leftTabPaths,
            fallbackDirectory: leftURL,
            activeIndex: session.wrappedValue.leftActiveTabIndex
        )
        state.rightPanel.restoreTabs(
            from: session.wrappedValue.rightTabPaths,
            fallbackDirectory: rightURL,
            activeIndex: session.wrappedValue.rightActiveTabIndex
        )
        // `restoreTabs` has already picked the location of the tab it could
        // actually restore — a path that no longer exists is dropped, and the
        // active index clamped. Only an explicit in-memory location, which is
        // to say a window being cloned, should override that.
        if let leftLocation = session.wrappedValue.leftLocation {
            state.leftPanel.adoptClonedLocation(leftLocation)
        }
        if let rightLocation = session.wrappedValue.rightLocation {
            state.rightPanel.adoptClonedLocation(rightLocation)
        }
        _appState = State(initialValue: state)
    }

    package var body: some View {
        MainWindowView()
            .environment(appState)
            .environment(env.columnLayouts)
            .focusedSceneValue(\.appState, appState)
            // The state built in `init` is discarded on every re-init — SwiftUI
            // keeps the first one — so the frontmost reference has to be taken
            // from the `@State` that actually survives, or it dangles and Cmd+N
            // falls back to the saved session instead of this window.
            .onAppear { env.mostRecentAppState = appState }
            .task { await env.start() }
            .onChange(of: controlActiveState) { _, newValue in
                if newValue == .key {
                    env.mostRecentAppState = appState
                }
            }
            .onChange(of: appState.leftPanel.state.location) { _, newLocation in
                env.bookmarkStore.save(url: newLocation.persistentDirectory)
                captureSession()
            }
            .onChange(of: appState.rightPanel.state.location) { _, newLocation in
                env.bookmarkStore.save(url: newLocation.persistentDirectory)
                captureSession()
            }
            // Opening, closing, reordering or switching tabs usually leaves the
            // panel's location alone, so the location observers above would
            // never see it. This one does.
            .onChange(of: tabLayout) { _, _ in
                captureSession()
            }
            .onChange(of: session) { _, newValue in
                // Only the window the user is actually in defines what the next
                // launch resumes; otherwise a background window's incidental
                // change overwrites the layout of the one in front. Restoring
                // every window would mean a snapshot per `session.id`.
                guard controlActiveState == .key else { return }
                env.rememberLastSession(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .lcdrConfigurationApplied)) { _ in
                Task { await appState.applyEffectiveConfiguration() }
            }
    }

    /// Everything about the tabs that is worth persisting, in one comparable
    /// value — `PanelTab` itself carries a directory listing, which is far too
    /// much to diff on every reload.
    private struct TabLayout: Equatable {
        let leftPaths: [String]
        let rightPaths: [String]
        let leftActiveIndex: Int
        let rightActiveIndex: Int
    }

    private var tabLayout: TabLayout {
        TabLayout(
            leftPaths: appState.leftPanel.tabPathsForSession(),
            rightPaths: appState.rightPanel.tabPathsForSession(),
            leftActiveIndex: appState.leftPanel.state.activeTabIndex,
            rightActiveIndex: appState.rightPanel.state.activeTabIndex
        )
    }

    /// Rebuilds the session from the live panels. Writing it back to the
    /// binding both feeds macOS window restoration and, through the `session`
    /// observer, records the state for the next launch.
    private func captureSession() {
        let leftLocation = appState.leftPanel.state.location
        let rightLocation = appState.rightPanel.state.location
        session = PanelSession(
            id: session.id,
            leftPath: leftLocation.persistentDirectory.path,
            rightPath: rightLocation.persistentDirectory.path,
            leftTabPaths: appState.leftPanel.tabPathsForSession(),
            rightTabPaths: appState.rightPanel.tabPathsForSession(),
            leftActiveTabIndex: appState.leftPanel.state.activeTabIndex,
            rightActiveTabIndex: appState.rightPanel.state.activeTabIndex,
            leftLocation: leftLocation,
            rightLocation: rightLocation
        )
    }
}
