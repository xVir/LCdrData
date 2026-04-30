import SwiftUI

/// Bottom command bar with function-key labels reminiscent of classic orthodox
/// file managers. Each button shows the key hint and action name.
/// Wired to file operations via closures provided by the parent view.
struct CommandBarView: View {

    let canViewOrEditFile: Bool
    let hasSelection: Bool
    let onView: () -> Void
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onMove: () -> Void
    let onMkdir: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(commands, id: \.key) { command in
                CommandButton(command: command)
            }
        }
        .frame(height: 28)
        .background(.bar)
    }

    // MARK: - Command Definitions

    private struct CommandDef: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let isEnabled: Bool
        let action: () -> Void
    }

    private var commands: [CommandDef] {
        [
            CommandDef(key: "F3", label: "View", isEnabled: canViewOrEditFile, action: onView),
            CommandDef(key: "F4", label: "Edit", isEnabled: canViewOrEditFile, action: onEdit),
            CommandDef(key: "F5", label: "Copy", isEnabled: hasSelection, action: onCopy),
            CommandDef(key: "F6", label: "Move", isEnabled: hasSelection, action: onMove),
            CommandDef(key: "F7", label: "Mkdir", isEnabled: true, action: onMkdir),
            CommandDef(key: "F8", label: "Delete", isEnabled: hasSelection, action: onDelete),
        ]
    }

    // MARK: - Command Button

    private struct CommandButton: View {
        let command: CommandDef

        var body: some View {
            Button {
                command.action()
            } label: {
                HStack(spacing: 3) {
                    Text(command.key)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text(command.label)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!command.isEnabled)
        }
    }
}

#Preview {
    CommandBarView(
        canViewOrEditFile: true,
        hasSelection: true,
        onView: {},
        onEdit: {},
        onCopy: {},
        onMove: {},
        onMkdir: {},
        onDelete: {}
    )
}
