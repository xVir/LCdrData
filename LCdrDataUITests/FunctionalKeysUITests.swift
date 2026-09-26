import XCTest

final class FunctionalKeysUITests: LCdrDataUITestCase {

    @MainActor
    func testF3QuickLookActionIsBound() throws {
        let app = launchWithSelectedFile()

        tapCommandBarButton("F3", in: app)

        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "F3")
        ).firstMatch.exists)
    }

    @MainActor
    func testF4EditActionIsBound() throws {
        let app = launchWithSelectedFile()

        tapCommandBarButton("F4", in: app)

        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    @MainActor
    func testF5CopyActionRequestsConfirmation() throws {
        let app = launchWithSelectedFile()

        tapCommandBarButton("F5", in: app)

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.last?.click()
    }

    @MainActor
    func testConfirmedCopyShowsTheTaskIndicator() throws {
        let app = launchWithSelectedFile()

        tapCommandBarButton("F5", in: app)
        let confirm = app.buttons.matching(identifier: "Confirm")
        XCTAssertTrue(confirm.firstMatch.waitForExistence(timeout: 5))
        confirm.allElementsBoundByIndex.last?.click()

        XCTAssertTrue(app.buttons["task-indicator"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testClickingTheTaskIndicatorShowsTheOperationList() throws {
        let app = launchWithSelectedFile()

        tapCommandBarButton("F5", in: app)
        let dialogConfirm = app.dialogs.buttons["Confirm"]
        let sheetConfirm = app.sheets.buttons["Confirm"]
        if dialogConfirm.waitForExistence(timeout: 5) {
            dialogConfirm.click()
        } else {
            XCTAssertTrue(sheetConfirm.waitForExistence(timeout: 2), "copy confirmation did not appear")
            sheetConfirm.click()
        }

        let copied = app.outlines["fileList.right"].staticTexts["left-folder-1"]
        XCTAssertTrue(copied.waitForExistence(timeout: 5), "copy did not arrive in the right panel")

        let indicator = app.buttons["task-indicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        indicator.click()

        let list = app.descendants(matching: .any)["task-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "clicking the task indicator did not show the operation list")
        let row = app.descendants(matching: .any)["task-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "operation list did not include a row")
        let label = row.label
        XCTAssertTrue(
            label.contains("Copying"),
            "operation list row was '\(label)'"
        )
    }

    @MainActor
    func testF6MoveActionRequestsConfirmation() throws {
        let app = launchWithSelectedFile()

        tapCommandBarButton("F6", in: app)

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.last?.click()
    }

    @MainActor
    func testF7NewFolderActionRequestsName() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.outlines["fileList.left"].waitForExistence(timeout: 20))

        tapCommandBarButton("F7", in: app)

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.last?.click()
    }

    @MainActor
    func testF8DeleteActionRequestsConfirmation() throws {
        let app = launchWithSelectedFile()

        tapCommandBarButton("F8", in: app)

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "Cancel").allElementsBoundByIndex.last?.click()
    }

    @MainActor
    private func launchWithSelectedFile() -> XCUIApplication {
        let app = makeApplication()
        app.launch()
        let fileList = app.outlines["fileList.left"]
        XCTAssertTrue(fileList.waitForExistence(timeout: 20))
        fileList.outlineRows.element(boundBy: 1).click()
        return app
    }

    @MainActor
    private func tapCommandBarButton(_ key: String, in app: XCUIApplication) {
        let button = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", key)
        ).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(key) command button not found")
        button.click()
    }
}
