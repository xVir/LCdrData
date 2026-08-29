import SwiftUI
import Models
import Services
import ViewModels
import AppEnvironment

/// Bottom command bar with function-key labels reminiscent of classic orthodox
/// file managers. Each button shows the key hint and action name, runs its
/// `Command` through `appState.commands`, and enables/disables itself from the
/// runner.
package struct CommandBarView: View {

    package let appState: AppState

    package var body: some View {
        HStack(spacing: 0) {
            ForEach(entries) { entry in
                CommandButton(
                    key: entry.key,
                    label: entry.label,
                    isEnabled: appState.commands.isEnabled(entry.command),
                    action: { appState.commands.perform(entry.command) }
                )
            }
        }
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Command Definitions

    private struct Entry: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let command: Command
    }

    private var entries: [Entry] {
        [
            Entry(key: "F3", label: "View", command: .quickLook),
            Entry(key: "F4", label: "Edit", command: .edit),
            Entry(key: "F5", label: "Copy", command: .copy),
            Entry(key: "F6", label: "Move", command: .move),
            Entry(key: "F7", label: "Mkdir", command: .newFolder),
            Entry(key: "F8", label: "Delete", command: .trash),
        ]
    }

    // MARK: - Command Button

    private struct CommandButton: View {
        let key: String
        let label: String
        let isEnabled: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(key)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text(label)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(highlight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            // A disabled command is not clickable, so it must not look
            // clickable either — the hover tracking only applies when enabled.
            .onHover { hovering in
                isHovering = hovering && isEnabled
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { isHovering = false }
            }
        }

        @ViewBuilder
        private var highlight: some View {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .animation(.easeOut(duration: 0.12), value: isHovering)
        }
    }
}

#Preview {
    CommandBarView(appState: AppState())
}
