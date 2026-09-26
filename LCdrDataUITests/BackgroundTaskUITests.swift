import XCTest

/// Copies are paced with `--operation-item-delay-ms` so a multi-file copy stays
/// on screen long enough to watch the bar, cancel it, or queue another one.
final class BackgroundTaskUITests: LCdrDataUITestCase {

    private let filesPerBatch = 8
    private let itemDelayMilliseconds = 400

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fileManager = FileManager.default
        let existing = try fileManager.contentsOfDirectory(
            at: leftFixtureDirectory,
            includingPropertiesForKeys: nil
        )
        for url in existing {
            try fileManager.removeItem(at: url)
        }
        try writeBatch(named: "batch1", count: filesPerBatch)
        try writeBatch(named: "batch2", count: filesPerBatch)
    }

    @MainActor
    func testRunningCopyShowsAProgressBarThatAdvancesAndTheFinishedRowStays() throws {
        let app = launchPacedApp()
        copyBatch("batch1", in: app)
        openTaskList(in: app)

        XCTAssertTrue(
            app.progressIndicators["task-progress"].waitForExistence(timeout: 5),
            "running copy did not show a progress bar"
        )

        var readings: Set<String> = []
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && readings.count < 2 {
            readings.formUnion(progressReadings(in: app))
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        XCTAssertGreaterThanOrEqual(
            readings.count,
            2,
            "progress bar did not change. readings=\(readings.sorted())"
        )

        let finished = taskRows(in: app).matching(
            NSPredicate(format: "label CONTAINS %@", ", Finished")
        ).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 8), "copy did not finish")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(finished.exists, "finished copy left the list")
    }

    @MainActor
    func testCancelButtonStopsTheCopyAndTheCancelledRowStays() throws {
        let app = launchPacedApp()
        copyBatch("batch1", in: app)
        openTaskList(in: app)

        let cancel = app.descendants(matching: .any)["task-list"].buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "running copy has no Cancel button")
        cancel.click()

        let cancelled = taskRows(in: app).matching(
            NSPredicate(format: "label CONTAINS %@", ", Cancelled")
        ).firstMatch
        XCTAssertTrue(cancelled.waitForExistence(timeout: 5), "cancelling the copy did not mark it cancelled")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(cancelled.exists, "cancelled copy left the list")
    }

    @MainActor
    func testCopyPastTheAllowanceWaitsThenRunsWhenASlotFrees() throws {
        let app = launchPacedApp(maxActive: 1)
        copyBatch("batch1", in: app)
        copyBatch("batch2", in: app)
        openTaskList(in: app)

        let waiting = taskRows(in: app).matching(
            NSPredicate(format: "label CONTAINS %@", ", Waiting")
        ).firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 5), "copy past the allowance did not wait")

        let runningAfter = taskRows(in: app).matching(
            NSPredicate(format: "label CONTAINS %@", ", Running")
        )
        let finished = taskRows(in: app).matching(
            NSPredicate(format: "label CONTAINS %@", ", Finished")
        ).firstMatch
        XCTAssertTrue(finished.waitForExistence(timeout: 10), "the first copy did not finish")
        XCTAssertFalse(waiting.exists, "waiting copy did not start when a slot freed")
        XCTAssertTrue(runningAfter.firstMatch.exists, "the waiting copy did not become running")
        XCTAssertTrue(finished.exists, "finished copy left the list")
    }

    @MainActor
    private func launchPacedApp(maxActive: Int? = nil) -> XCUIApplication {
        let app = makeApplication()
        app.launchArguments.append(contentsOf: [
            "--operation-item-delay-ms", "\(itemDelayMilliseconds)",
        ])
        if let maxActive {
            app.launchArguments.append(contentsOf: ["--operation-max-active", "\(maxActive)"])
        }
        app.launch()
        XCTAssertTrue(app.outlines["fileList.left"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor
    private func copyBatch(_ name: String, in app: XCUIApplication) {
        let list = app.outlines["fileList.left"]
        let first = list.staticTexts["\(name)-01.txt"]
        let last = list.staticTexts["\(name)-\(String(format: "%02d", filesPerBatch)).txt"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "\(name) files are not in the left panel")
        first.click()
        XCUIElement.perform(withKeyModifiers: .shift) {
            last.click()
        }

        let copy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "F5")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.click()

        let dialogConfirm = app.dialogs.buttons["Confirm"]
        let sheetConfirm = app.sheets.buttons["Confirm"]
        if dialogConfirm.waitForExistence(timeout: 5) {
            dialogConfirm.click()
        } else {
            XCTAssertTrue(sheetConfirm.waitForExistence(timeout: 2), "copy confirmation did not appear")
            sheetConfirm.click()
        }
    }

    @MainActor
    private func openTaskList(in app: XCUIApplication) {
        let indicator = app.buttons["task-indicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        if !app.descendants(matching: .any)["task-list"].exists {
            indicator.click()
        }
        XCTAssertTrue(app.descendants(matching: .any)["task-list"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func taskRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "task-row")
    }

    @MainActor
    private func progressReadings(in app: XCUIApplication) -> [String] {
        app.progressIndicators.matching(identifier: "task-progress").allElementsBoundByIndex.compactMap { indicator in
            if let value = indicator.value as? String, !value.isEmpty {
                return value
            }
            return indicator.label.isEmpty ? nil : indicator.label
        }
    }

    private func writeBatch(named name: String, count: Int) throws {
        for index in 1...count {
            let file = leftFixtureDirectory.appendingPathComponent(
                "\(name)-\(String(format: "%02d", index)).txt"
            )
            try Data("\(name) \(index)\n".utf8).write(to: file)
        }
    }
}
