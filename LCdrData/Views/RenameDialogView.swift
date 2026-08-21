import SwiftUI
import Core
import Services
import ViewModels
import AppEnvironment

/// A sheet dialog for renaming a file or directory.
/// Uses its own `@State` for the text field so the name is always
/// initialized fresh from the item — no stale binding issues.
package struct RenameDialogView: View {

    package let item: FileItem
    package let onRename: (String) -> Void

    @State private var newName: String
    @Environment(\.dismiss) private var dismiss

    package init(item: FileItem, onRename: @escaping (String) -> Void) {
        self.item = item
        self.onRename = onRename
        self._newName = State(initialValue: item.name)
    }

    package var body: some View {
        VStack(spacing: 16) {
            Text("Rename")
                .font(.headline)

            Text("Enter a new name for \"\(item.name)\":")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { confirmRename() }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    confirmRename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func confirmRename() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else {
            dismiss()
            return
        }
        onRename(trimmed)
        dismiss()
    }
}
