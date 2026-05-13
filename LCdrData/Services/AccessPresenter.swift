import AppKit
import Foundation

/// Abstracts the user-facing flow that asks for sandbox folder access. The
/// production implementation drives NSAlert + NSOpenPanel; tests inject a
/// fake that returns deterministic results.
protocol AccessPresenter: Sendable {
    func present(_ context: AccessRequestContext) async -> URL?
}

/// A presenter that always cancels — used as a safe default for tests and
/// previews that never need to drive the access dialog.
struct NoopAccessPresenter: AccessPresenter {
    func present(_ context: AccessRequestContext) async -> URL? { nil }
}

/// Production presenter: shows the existing NSOpenPanel pre-navigated to the
/// context's suggested folder. The NSAlert layer (with hybrid symlink copy,
/// "Skip for Now" wording, etc.) lands in the follow-on commit; until then
/// this preserves current behaviour.
@MainActor
struct NSOpenPanelAccessPresenter: AccessPresenter {

    func present(_ context: AccessRequestContext) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        switch context {
        case .startup:
            panel.title = "Grant Home Folder Access"
            panel.message = "LCdrData needs permission to access your Home folder to browse your files."
            panel.prompt = "Grant Access"
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        case .reactive(let displayURL, let resolvedTarget):
            panel.title = "Grant Access to Folder"
            panel.message = "LCdrData needs permission to access \"\(displayURL.lastPathComponent)\"."
            panel.prompt = "Grant Access"
            panel.directoryURL = resolvedTarget
        case .manualGrant(let suggestedURL):
            panel.title = "Grant Folder Access"
            panel.message = "Select a folder to grant LCdrData access to."
            panel.prompt = "Grant Access"
            panel.directoryURL = suggestedURL
        }

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else { return nil }
        return url
    }
}
