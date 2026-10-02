import AppKit
import SwiftUI
import Models
import Utilities
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
            if operations.ringIsEmpty {
                fraction = 0
                arc = Color(nsColor: .systemBlue)
            } else {
                fraction = 1
                arc = hasFailure ? .red : Color(nsColor: .systemBlue)
            }
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

/// Rows for the task list. Running, waiting, and recent operations are grouped.
/// A running row keeps the same title line as a settled one, with a thin bar underneath.
package struct TaskListView: View {

    @Bindable var operations: FileOperationViewModel

    package var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tasks")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.operations) { operation in
                            TaskRow(operation: operation) {
                                operations.cancel(id: operation.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-list")
    }

    private var sections: [TaskSection] {
        let visible = operations.visibleOperations
        let running = visible.filter { $0.status == .inProgress }
        let waiting = visible.filter { $0.status == .pending }
        let recent = visible.filter { operation in
            switch operation.status {
            case .completed, .failed, .cancelled:
                return true
            case .pending, .inProgress:
                return false
            }
        }
        return [
            TaskSection(id: "running", title: "Running", operations: running),
            TaskSection(id: "waiting", title: "Waiting", operations: waiting),
            TaskSection(id: "recent", title: "Recent", operations: recent),
        ].filter { !$0.operations.isEmpty }
    }
}

private struct TaskSection: Identifiable {
    let id: String
    let title: String
    let operations: [FileOperation]
}

/// One operation. The title line matches a settled row; a running row adds a thin bar.
private struct TaskRow: View {

    var operation: FileOperation
    var onCancel: () -> Void

    @Environment(\.lcPanelFontSize) private var panelFontSize
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            kindMark
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 6) {
                    Text(operation.displayDescription)
                        .font(.system(size: panelFontSize))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailingMark
                }
                if let detail = detailText {
                    Text(detail)
                        .font(.system(size: detailFontSize))
                        .foregroundStyle(isFailed ? Color(nsColor: .systemRed) : .secondary)
                        .lineLimit(isFailed ? 2 : 1)
                        .truncationMode(.middle)
                }
                if operation.status == .inProgress {
                    ProgressView(value: operation.progress?.fractionCompleted ?? 0)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .tint(Color(nsColor: .systemBlue))
                        .accessibilityIdentifier("task-progress")
                        .accessibilityValue(progressValue)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row")
        .accessibilityLabel("\(operation.displayDescription), \(statusTitle)")
    }

    private var detailFontSize: CGFloat {
        max(11, panelFontSize - 2)
    }

    private var isFailed: Bool {
        if case .failed = operation.status { return true }
        return false
    }

    /// Running and waiting rows can be cancelled. Finished rows cannot.
    private var showsCancel: Bool {
        operation.status == .inProgress || operation.status == .pending
    }

    private var kindMark: some View {
        let style = kindStyle(operation.kind)
        return Image(systemName: style.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(style.tint)
            .frame(width: 22, height: 22)
            .background(style.tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }

    private var trailingMark: some View {
        ZStack {
            statusGlyph
                .opacity(isHovering && showsCancel ? 0 : 1)
                .accessibilityHidden(true)
            if showsCancel {
                cancelButton
            }
        }
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch operation.status {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemGreen))
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemRed))
        case .cancelled:
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        case .inProgress:
            EmptyView()
        }
    }

    /// The glyph is hidden until the row is hovered. The button stays in the
    /// accessibility tree, so it can be activated without the pointer resting on it.
    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
                .opacity(isHovering ? 1 : 0)
                .background(Color.primary.opacity(0.001))
                .contentShape(Rectangle())
        }
        .buttonStyle(CancelIconButtonStyle())
        .accessibilityLabel("Cancel")
    }

    private var statusTitle: String {
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

    private var progressValue: String {
        guard let progress = operation.progress else { return "0 of 0" }
        return "\(progress.completedItems) of \(progress.totalItems)"
    }

    /// Destination, or the failure text when the operation did not succeed.
    /// While running, the file currently being handled is appended.
    private var detailText: String? {
        if case .failed(let message) = operation.status {
            let place = operation.locationDescription()
            return place.isEmpty ? message : "\(place) — \(message)"
        }
        let place = operation.locationDescription()
        if operation.status == .inProgress {
            return runningDetail(place: place)
        }
        return place.isEmpty ? nil : place
    }

    private func runningDetail(place: String) -> String {
        if operation.isFinishingCurrentItem {
            let name = operation.progress?.currentItemName ?? "current item"
            let finishing = "Finishing \(name)"
            return place.isEmpty ? finishing : "\(place) — \(finishing)"
        }
        if let name = operation.progress?.currentItemName, !name.isEmpty {
            return place.isEmpty ? name : "\(place) — \(name)"
        }
        return place.isEmpty ? "Starting" : place
    }

    private func kindStyle(_ kind: FileOperationKind) -> (symbol: String, tint: Color) {
        switch kind {
        case .copy:
            return ("doc.on.doc", Color(nsColor: .systemBlue))
        case .move:
            return ("arrow.right", Color(nsColor: .systemOrange))
        case .delete:
            return ("trash", Color(nsColor: .systemRed).opacity(0.65))
        case .permanentDelete:
            return ("trash.slash", Color(nsColor: .systemRed))
        case .createFolder:
            return ("folder.badge.plus", Color(nsColor: .systemBlue))
        case .rename:
            return ("pencil", Color(nsColor: .systemBlue))
        }
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
