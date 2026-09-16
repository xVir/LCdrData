import XCTest

final class SessionRestoreUITests: LCdrDataUITestCase {

    private static let rowIdentifierPrefix = "fileRow.left."

    /// Explicit fixture arguments must win over any state macOS or the app may
    /// have restored from an earlier run.
    @MainActor
    func testPanelDirectoriesResetToFixturesAfterRelaunch() throws {
        // Arrange
        let app = makeApplication()
        app.launch()

        let fileList = app.outlines["fileList.left"]
        XCTAssertTrue(fileList.waitForExistence(timeout: 20), "left panel file list never appeared")

        let folderName = "left-folder-1"
        let expectedPath = leftFixtureDirectory.appendingPathComponent(folderName).path

        // Act — enter a subdirectory, then relaunch from scratch.
        doubleClickRow(Self.rowIdentifierPrefix + folderName, in: fileList)
        XCTAssertTrue(
            waitForLeftPanelPath(expectedPath, in: app),
            "first run did not enter \(folderName); still at \(leftPanelPath(in: app))"
        )

        app.terminate()
        app.launch()

        // Assert — explicit launch arguments reset the panel to the fixture root.
        let reset = waitForLeftPanelPath(leftFixtureDirectory.path, in: app)
        let observed = leftPanelPath(in: app)

        XCTAssertTrue(reset, "relaunch opened \(observed) instead of the fixture root")
    }

    // MARK: - Helpers

    @MainActor
    private func leftPanelPath(in app: XCUIApplication) -> String {
        let pathBar = app.scrollViews["pathBar.left"].firstMatch
        guard pathBar.exists else { return "" }
        return pathBar.value as? String ?? ""
    }

    @MainActor
    private func waitForLeftPanelPath(
        _ expected: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 15
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if leftPanelPath(in: app) == expected { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func doubleClickRow(_ identifier: String, in fileList: XCUIElement) {
        fileList.staticTexts[identifier].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .doubleClick()
    }

}
