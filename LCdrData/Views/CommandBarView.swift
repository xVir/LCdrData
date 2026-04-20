//
//  CommandBarView.swift
//  LCdrData
//
//  Created by Dima Skachkov on 02.04.2026.
//

import SwiftUI

/// Bottom command bar with function-key labels reminiscent of classic orthodox
/// file managers. Each button shows the key hint and action name.
/// In Phase 1, buttons are visual placeholders; actual operations come in Phase 2.
struct CommandBarView: View {

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
    }

    private var commands: [CommandDef] {
        [
            CommandDef(key: "F3", label: "View", isEnabled: false),
            CommandDef(key: "F4", label: "Edit", isEnabled: false),
            CommandDef(key: "F5", label: "Copy", isEnabled: false),
            CommandDef(key: "F6", label: "Move", isEnabled: false),
            CommandDef(key: "F7", label: "Mkdir", isEnabled: false),
            CommandDef(key: "F8", label: "Delete", isEnabled: false),
        ]
    }

    // MARK: - Command Button

    private struct CommandButton: View {
        let command: CommandDef

        var body: some View {
            Button {
                // Actions will be wired in Phase 2
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
    CommandBarView()
}
