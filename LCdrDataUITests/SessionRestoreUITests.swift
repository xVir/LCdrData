import XCTest

final class SessionRestoreUITests: XCTestCase {

    private static let rowIdentifierPrefix = "fileRow.left."
    private static let parentRowIdentifier = "fileRow.left..."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The panels must come back on the directories they were left on, without
    /// depending on macOS window restoration (which is skipped whenever the app
    /// is killed rather than quit, and whenever "Close windows when quitting an
    /// application" is enabled).
    ///
    /// The test steps back out of the subdirectory at the end, so the directory
    /// it leaves behind is always one that is known to contain a subfolder and
    /// repeated runs stay stable.
    @MainActor
    func testPanelDirectoriesSurviveARelaunch() throws {
        // Arrange — first run: step into a subdirectory of wherever we start.
        let app = XCUIApplication()
        app.launch()

        let fileList = app.outlines["fileList.left"]
        XCTAssertTrue(fileList.waitForExistence(timeout: 20), "left panel file list never appeared")

        let (startingPath, folderName) = try anchorOnDirectoryWithASubfolder(app: app, fileList: fileList)
        let expectedPath = startingPath + "/" + folderName

        // Act — enter it, then relaunch the app from scratch.
        doubleClickRow(Self.rowIdentifierPrefix + folderName, in: fileList)
        XCTAssertTrue(
            waitForLeftPanelPath(expectedPath, in: app),
            "first run did not enter \(folderName); still at \(leftPanelPath(in: app))"
        )

        app.terminate()
        app.launch()

        // Assert — the second run resumes where the first one ended, rather than
        // falling back to the directory it would open on a first launch.
        let resumed = waitForLeftPanelPath(expectedPath, in: app)
        let observed = leftPanelPath(in: app)

        // Leave the persisted directory as we found it, whatever the outcome.
        doubleClickRow(Self.parentRowIdentifier, in: fileList)
        _ = waitForLeftPanelPath(startingPath, in: app)

        XCTAssertTrue(resumed, "relaunch opened \(observed) instead of resuming \(expectedPath)")
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

    /// Walks up until the listing offers a plain subdirectory to step into, so
    /// the test works from whatever directory the previous run left behind.
    @MainActor
    private func anchorOnDirectoryWithASubfolder(
        app: XCUIApplication,
        fileList: XCUIElement
    ) throws -> (path: String, folderName: String) {
        for _ in 0..<4 {
            let path = leftPanelPath(in: app)
            XCTAssertFalse(path.isEmpty, "could not read the left panel's path")

            if let folder = firstSubfolderName(in: fileList) {
                return (path, folder)
            }
            guard fileList.staticTexts[Self.parentRowIdentifier].firstMatch.exists else { break }
            doubleClickRow(Self.parentRowIdentifier, in: fileList)
            _ = waitForLeftPanelPath((path as NSString).deletingLastPathComponent, in: app)
        }
        throw XCTSkip("found no directory with a plain subfolder to step into")
    }

    /// The first plain subdirectory of the current listing — skips `..` and
    /// symlink aliases, which report other kinds.
    @MainActor
    private func firstSubfolderName(in fileList: XCUIElement) -> String? {
        for row in fileList.outlineRows.allElementsBoundByIndex {
            let texts = row.staticTexts.allElementsBoundByIndex
            guard texts.last?.value as? String == "Folder",
                  let identifier = texts.first?.identifier,
                  identifier.hasPrefix(Self.rowIdentifierPrefix) else {
                continue
            }
            return String(identifier.dropFirst(Self.rowIdentifierPrefix.count))
        }
        return nil
    }
}
