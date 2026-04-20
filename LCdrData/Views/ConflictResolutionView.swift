//
//  ConflictResolutionView.swift
//  LCdrData
//
//  Created by Dima Skachkov on 20.04.2026.
//

import SwiftUI

/// Dialog presented when a file operation encounters a naming conflict.
/// Offers options to overwrite, skip, or rename, with an "Apply to All" checkbox.
struct ConflictResolutionView: View {

    let conflict: FileConflict
    let onResolve: (ConflictResolution, Bool) -> Void

    @State private var applyToAll: Bool = false
    @State private var customName: String = ""

    private var conflictFileName: String {
        switch conflict {
        case .destinationExists(_, let destination):
            return destination.lastPathComponent
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("File Already Exists")
                        .font(.headline)
                    Text("An item named \"\(conflictFileName)\" already exists at the destination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Rename option
            HStack {
                Text("Rename as:")
                    .font(.caption)
                TextField("New name", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
                Button("Rename") {
                    let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    onResolve(.rename(newName: name), applyToAll)
                }
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            // Apply to all toggle
            Toggle("Apply to all conflicts", isOn: $applyToAll)
                .font(.caption)

            // Action buttons
            HStack(spacing: 12) {
                Button("Skip") {
                    onResolve(.skip, applyToAll)
                }
                .keyboardShortcut(.cancelAction)

                Button("Overwrite") {
                    onResolve(.overwrite, applyToAll)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        .onAppear {
            customName = suggestAlternateName(for: conflictFileName)
        }
    }

    /// Suggests an alternate name by appending " (copy)" before the extension.
    private func suggestAlternateName(for name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent

        if ext.isEmpty {
            return "\(base) (copy)"
        } else {
            return "\(base) (copy).\(ext)"
        }
    }
}
