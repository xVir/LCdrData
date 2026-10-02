import Testing
import Foundation
@testable import Models

struct TaskListPolicyTests {

    private let policy = TaskListPolicy()

    @Test func showsEveryRunningAndWaitingOperationBeforeHistory() {
        let running = [operation(name: "running-old"), operation(name: "running-new")]
        let waiting = [operation(name: "waiting-next", status: .pending)]
        let settled = (0..<12).map { operation(name: "settled-\($0)", status: .completed) }

        let visible = policy.visible(
            running: running,
            waiting: waiting,
            settledNewestLast: settled
        )

        #expect(visible.map(\.id) == [
            running[0].id,
            running[1].id,
            waiting[0].id,
        ] + settled.suffix(7).reversed().map(\.id))
    }

    @Test func historyAloneIsTheTenNewestFinishedFirst() {
        let settled = (0..<15).map { operation(name: "settled-\($0)", status: .completed) }

        let visible = policy.visible(running: [], waiting: [], settledNewestLast: settled)

        #expect(visible.map(\.id) == settled.suffix(10).reversed().map(\.id))
    }

    @Test func combinedProgressIgnoresWaitingOperations() {
        let running = [
            operation(
                name: "almost",
                progress: FileOperationProgress(totalItems: 10, completedItems: 9, currentItemName: "a")
            ),
            operation(
                name: "fresh",
                progress: FileOperationProgress(totalItems: 10, completedItems: 0, currentItemName: "b")
            ),
        ]
        let waiting = [
            operation(
                name: "queued",
                status: .pending,
                progress: FileOperationProgress(totalItems: 10, completedItems: 10, currentItemName: "c")
            ),
        ]

        #expect(policy.aggregateFraction(running: running) == 9.0 / 20.0)
        #expect(policy.aggregateFraction(running: []) == nil)
        #expect(
            policy.indicatorState(running: running, waiting: waiting, settled: [])
                == .running(fraction: 9.0 / 20.0)
        )
    }

    @Test func indicatorIsRedOnlyForAnUnacknowledgedFailure() {
        let settled = [
            operation(name: "ok", status: .completed),
            operation(name: "bad", status: .failed("disk full")),
        ]

        #expect(
            policy.indicatorState(
                running: [],
                waiting: [],
                settled: settled,
                unacknowledgedFailure: true
            ) == .settled(hasFailure: true)
        )
        #expect(
            policy.indicatorState(running: [], waiting: [], settled: settled) == .settled(hasFailure: false)
        )
    }

    @Test func indicatorIsHiddenWhenNothingIsLeft() {
        #expect(policy.indicatorState(running: [], waiting: [], settled: []) == .hidden)
    }

    private func operation(
        name: String,
        status: FileOperationStatus = .inProgress,
        progress: FileOperationProgress? = nil
    ) -> FileOperation {
        FileOperation(
            kind: .copy,
            sourceURLs: [URL(fileURLWithPath: "/\(name)")],
            status: status,
            progress: progress
        )
    }
}
