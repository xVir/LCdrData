import SwiftUI
import Models
import Services
import ViewModels
import AppEnvironment

/// Overlay view showing progress for long-running file operations (copy/move).
/// Displays a progress bar, current item name, and a cancel button.
package struct FileOperationProgressView: View {

    package let operations: [FileOperation]
    package let onCancel: () -> Void

    package var body: some View {
        VStack(spacing: 16) {
            ForEach(operations) { operation in
                operationRow(operation)
            }

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 350)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }

    @ViewBuilder
    private func operationRow(_ operation: FileOperation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(operation.displayDescription)
                .font(.headline)

            if let progress = operation.progress {
                ProgressView(value: progress.fractionCompleted) {
                    Text(progress.currentItemName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text("\(progress.completedItems) of \(progress.totalItems)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
