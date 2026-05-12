import SwiftUI

@main
struct LCdrDataApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup(for: PanelSession.self) { $session in
            WindowRootView(session: $session, env: env)
        } defaultValue: {
            env.makeFreshSession()
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands { MainCommands(env: env) }

        Settings {
            ConfigurationView(configuration: env.configuration)
        }
    }
}

// MARK: - Focused scene value

struct ActiveAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[ActiveAppStateKey.self] }
        set { self[ActiveAppStateKey.self] = newValue }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let lcdrConfigurationApplied = Notification.Name("LCDR.configurationApplied")
}
