import SwiftUI
import Models
import Services
import ViewModels
import AppEnvironment
import Views

@main
struct LCdrDataApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()

    init() {
        appDelegate.environment = env
    }

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
