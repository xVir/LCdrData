import AppKit
import SwiftUI
import Models
import ViewModels

/// The title-bar ring and the list it opens.
package struct TaskIndicatorButton: View {

    @Bindable var operations: FileOperationViewModel

    package var body: some View {
        let state = operations.indicatorState
        Button {
            operations.toggleTaskList()
        } label: {
            ring(for: state)
                .frame(width: 16, height: 16)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task-indicator")
        .accessibilityLabel(accessibilityLabel(for: state))
        .opacity(state == .hidden ? 0 : 1)
        .allowsHitTesting(state != .hidden)
    }

    private func ring(for state: TaskIndicatorState) -> some View {
        let fraction: Double
        let arc: Color
        switch state {
        case .hidden:
            fraction = 0
            arc = .secondary
        case .running(let value):
            fraction = value
            // The title bar redraws the accent as white. This blue is the progress fill.
            arc = Color(nsColor: .systemBlue)
        case .settled(let hasFailure):
            fraction = 1
            arc = hasFailure ? .red : Color(nsColor: .systemBlue)
        }
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(arc, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private func accessibilityLabel(for state: TaskIndicatorState) -> String {
        switch state {
        case .hidden:
            return "Background tasks"
        case .running(let fraction):
            let percent = Int((fraction * 100).rounded())
            return "Background tasks, \(percent) percent"
        case .settled(let hasFailure):
            return hasFailure ? "Background tasks, 1 failed" : "Background tasks, finished"
        }
    }
}

/// Rows for the task list. Each running operation has its own progress bar.
package struct TaskListView: View {

    @Bindable var operations: FileOperationViewModel

    package var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(operations.visibleOperations) { operation in
                taskRow(operation)
            }
        }
        .padding(12)
        .frame(width: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-list")
    }

    @ViewBuilder
    private func taskRow(_ operation: FileOperation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(operation.displayDescription)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(statusTitle(operation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if operation.status == .inProgress {
                HStack(alignment: .center, spacing: 8) {
                    ProgressView(value: operation.progress?.fractionCompleted ?? 0)
                        .tint(Color(nsColor: .systemBlue))
                        .accessibilityIdentifier("task-progress")
                        .accessibilityValue(progressValue(operation))
                    cancelButton(operation)
                }
                Text(detailLine(operation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let detail = settledDetail(operation) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if operation.status == .pending {
                HStack {
                    Spacer(minLength: 0)
                    cancelButton(operation)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row")
        .accessibilityLabel("\(operation.displayDescription), \(statusTitle(operation))")
    }

    private func cancelButton(_ operation: FileOperation) -> some View {
        Button {
            operations.cancel(id: operation.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(CancelIconButtonStyle())
        .accessibilityLabel("Cancel")
    }

    private func statusTitle(_ operation: FileOperation) -> String {
        switch operation.status {
        case .pending:
            return "Waiting"
        case .inProgress:
            return "Running"
        case .completed:
            return "Finished"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private func progressValue(_ operation: FileOperation) -> String {
        guard let progress = operation.progress else { return "0 of 0" }
        return "\(progress.completedItems) of \(progress.totalItems)"
    }

    private func detailLine(_ operation: FileOperation) -> String {
        let name = operation.progress?.currentItemName ?? "current item"
        if operation.isFinishingCurrentItem {
            return "Finishing \(name)"
        }
        if let progress = operation.progress {
            return "\(progress.currentItemName) — \(progress.completedItems) of \(progress.totalItems)"
        }
        return "Starting"
    }

    private func settledDetail(_ operation: FileOperation) -> String? {
        if case .failed(let message) = operation.status {
            return message
        }
        return nil
    }
}

/// Hover fills the circle lightly. Holding the mouse button fills it more.
private struct CancelIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CancelIconChrome(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct CancelIconChrome<Label: View>: View {
    var isPressed: Bool
    @ViewBuilder var label: () -> Label
    @State private var isHovering = false

    var body: some View {
        label()
            .padding(3)
            .background {
                Circle()
                    .fill(background)
            }
            .contentShape(Circle())
            .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isPressed {
            return Color.primary.opacity(0.28)
        }
        if isHovering {
            return Color.primary.opacity(0.12)
        }
        return Color.clear
    }
}
