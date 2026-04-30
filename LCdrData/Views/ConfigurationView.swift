import SwiftUI

/// Dual-pane KDL editor: read-only defaults (left) and user overrides (right), with Apply / Cancel.
struct ConfigurationView: View {

    @Environment(AppState.self) private var appState

    @State private var userKDL: String = ""
    @State private var applyError: String?
    @State private var defaultAttributed = AttributedString()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Configuration")
                .font(.title2)
                .padding([.top, .horizontal])

            Text("Left: bundled defaults (reference). Right: your overrides — saved only when you click Apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            HSplitView {
                defaultsPane
                    .frame(minWidth: 280)

                userPane
                    .frame(minWidth: 280)
            }
            .frame(minHeight: 360)

            if let applyError {
                Text(applyError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    syncUserFromDisk()
                    applyError = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    applyFromEditor()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 480)
        .task {
            await loadPanes()
        }
    }

    // MARK: - Subviews

    private var defaultsPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Defaults (read-only)")
                .font(.headline)
                .padding(.horizontal, 8)

            ScrollView {
                Text(defaultAttributed)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var userPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your configuration")
                .font(.headline)
                .padding(.horizontal, 8)

            TextEditor(text: $userKDL)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadPanes() async {
        let cfg = appState.configuration
        do {
            let defaultKDL = try cfg.defaultKDLText()
            defaultAttributed = KDLSyntaxHighlighter.attributedString(from: defaultKDL)
        } catch {
            let fallback = "// Could not load bundled defaults.\n\(error.localizedDescription)"
            defaultAttributed = AttributedString(fallback)
        }

        syncUserFromDisk()
    }

    private func syncUserFromDisk() {
        let cfg = appState.configuration
        do {
            userKDL = try cfg.userKDLText()
            if userKDL.isEmpty {
                userKDL = cfg.lastAppliedUserKDL
            }
        } catch {
            userKDL = cfg.lastAppliedUserKDL
        }
        applyError = nil
    }

    private func applyFromEditor() {
        do {
            try appState.configuration.apply(fromUserKDL: userKDL)
            applyError = nil
            Task {
                await appState.applyEffectiveConfiguration()
            }
        } catch let err as ConfigurationServiceError {
            switch err {
            case .invalidKDL(let message):
                applyError = message
            case .cannotCreateApplicationSupport:
                applyError = "Could not create the Application Support folder."
            case .cannotWriteUserFile:
                applyError = "Could not write the configuration file."
            }
        } catch {
            applyError = error.localizedDescription
        }
    }
}
