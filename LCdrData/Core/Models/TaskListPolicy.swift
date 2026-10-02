import Foundation

/// How full the title-bar ring is, and whether it is showing settled history.
package enum TaskIndicatorState: Equatable, Sendable {
    case hidden
    /// `fraction` is 0...1. Waiting-only windows use 0.
    case running(fraction: Double)
    case settled(hasFailure: Bool)
}

/// Which background tasks a window shows, and the combined progress of the running ones.
package struct TaskListPolicy: Sendable {

    package static let minimumSlots = 10
    package static let settledCapacity = 50

    package init() {}

    /// Running, then waiting, then the newest history that still fits.
    /// Every running and waiting task is included. History fills only the room left under 10.
    package func visible(
        running: [FileOperation],
        waiting: [FileOperation],
        settledNewestLast: [FileOperation]
    ) -> [FileOperation] {
        let cap = max(Self.minimumSlots, running.count + waiting.count)
        let historySlots = max(0, cap - running.count - waiting.count)
        let history = Array(settledNewestLast.suffix(historySlots).reversed())
        return running + waiting + history
    }

    /// Combined item progress of running tasks. Nil when nothing is running.
    /// A task that has not reported progress yet contributes nothing to either side.
    package func aggregateFraction(running: [FileOperation]) -> Double? {
        guard !running.isEmpty else { return nil }
        let totals = running.compactMap(\.progress)
        let totalItems = totals.reduce(0) { $0 + $1.totalItems }
        guard totalItems > 0 else { return 0 }
        let completedItems = totals.reduce(0) { $0 + $1.completedItems }
        return Double(completedItems) / Double(totalItems)
    }

    /// `unacknowledgedFailure` is a failure the task list has not been opened for.
    /// Older failures that are still in history do not keep the ring red.
    package func indicatorState(
        running: [FileOperation],
        waiting: [FileOperation],
        settled: [FileOperation],
        unacknowledgedFailure: Bool = false
    ) -> TaskIndicatorState {
        if !running.isEmpty {
            return .running(fraction: aggregateFraction(running: running) ?? 0)
        }
        if !waiting.isEmpty {
            return .running(fraction: 0)
        }
        guard !settled.isEmpty else { return .hidden }
        return .settled(hasFailure: unacknowledgedFailure)
    }
}
