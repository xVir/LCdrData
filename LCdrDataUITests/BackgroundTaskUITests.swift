import XCTest

/// Copies are paced with `--operation-item-delay-ms` so a multi-file copy stays
/// on screen long enough to watch the bar, cancel it, or queue another one.
final class BackgroundTaskUITests: LCdrDataUITestCase {

    private let filesPerBatch = 8
    /// Long enough that the test runner's pointer, which glides rather than jumps,
    /// still reaches Cancel before the copy finishes.
    private let itemDelayMilliseconds = 1200

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
    func testClickingEmptyPanelSpaceClosesTheTaskList() throws {
        let app = launchPacedApp(maxActive: nil, itemDelayMilliseconds: 0)
        copyBatch("batch1", in: app)
        openTaskList(in: app)

        clickEmptySpace(in: app.outlines["fileList.left"])

        let list = app.descendants(matching: .any)["task-list"]
        XCTAssertFalse(
            list.waitForExistence(timeout: 1),
            "clicking empty space in a panel left the task list open"
        )
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

        let cancel = app.descendants(matching: .any)["task-list"]
            .buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Cancel", "Cancel"))
            .firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "running copy has no Cancel button")
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
    private func launchPacedApp(
        maxActive: Int? = nil,
        itemDelayMilliseconds: Int? = nil
    ) -> XCUIApplication {
        let app = makeApplication()
        app.launchArguments.append(contentsOf: [
            "--operation-item-delay-ms", "\(itemDelayMilliseconds ?? self.itemDelayMilliseconds)",
        ])
        if let maxActive {
            app.launchArguments.append(contentsOf: ["--operation-max-active", "\(maxActive)"])
        }
        app.launch()
        XCTAssertTrue(app.outlines["fileList.left"].waitForExistence(timeout: 20))
        return app
    }

    /// Selects the batch and confirms the copy from the keyboard. The test
    /// runner glides the pointer, so clicking the first file, the last file,
    /// F5 and Confirm is most of the time spent before the copy even starts.
    @MainActor
    private func copyBatch(_ name: String, in app: XCUIApplication) {
        let list = app.outlines["fileList.left"]
        let firstName = "\(name)-01.txt"
        XCTAssertTrue(
            list.staticTexts[firstName].waitForExistence(timeout: 5),
            "\(name) files are not in the left panel"
        )

        let names = (try? FileManager.default.contentsOfDirectory(
            at: leftFixtureDirectory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()) ?? []
        let index = names.firstIndex(of: firstName) ?? 0

        app.typeKey(XCUIKeyboardKey.home, modifierFlags: [])
        // Home selects the first file and skips "..". If the table took Home
        // itself and landed on "..", step onto that first file.
        if list.outlineRows.element(boundBy: 0).isSelected {
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        }
        for _ in 0..<index {
            app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        }
        let targetRow = list.outlineRows.element(boundBy: index + 1)
        XCTAssertTrue(targetRow.isSelected, "could not select \(firstName)")
        // Arrow keys move the highlight. A range is a shift-click, and that
        // is the one pointer trip this setup still makes.
        let lastName = "\(name)-\(String(format: "%02d", filesPerBatch)).txt"
        let last = list.staticTexts[lastName]
        XCTAssertTrue(last.waitForExistence(timeout: 2), "\(lastName) is not in the left panel")
        XCUIElement.perform(withKeyModifiers: .shift) {
            last.click()
        }

        // F5 is the Copy shortcut. The C constant is not exposed as a Swift member.
        app.typeKey(XCUIKeyboardKey(rawValue: "\u{F708}"), modifierFlags: [])

        let dialogConfirm = app.dialogs.buttons["Confirm"]
        let sheetConfirm = app.sheets.buttons["Confirm"]
        let appeared = dialogConfirm.waitForExistence(timeout: 5) || sheetConfirm.exists
        XCTAssertTrue(appeared, "copy confirmation did not appear")
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
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
    private func clickEmptySpace(in fileList: XCUIElement) {
        let listFrame = fileList.frame
        let rows = fileList.outlineRows
        let lastRowMaxY = rows.element(boundBy: rows.count - 1).frame.maxY
        XCTAssertGreaterThan(
            listFrame.maxY - lastRowMaxY,
            24,
            "no blank area below the rows"
        )
        let emptyY = (lastRowMaxY + listFrame.maxY) / 2
        let normalizedY = (emptyY - listFrame.minY) / listFrame.height
        fileList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: normalizedY)).click()
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
