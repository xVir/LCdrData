import XCTest

final class PanelSelectionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Clicking the blank area below the last row must not leave the panel
    /// without a selected row — the cursor stays on the row it was on.
    @MainActor
    func testClickingEmptySpaceKeepsRowSelected() throws {
        // Arrange
        let app = XCUIApplication()
        app.launch()

        let fileList = app.outlines["fileList.left"]
        XCTAssertTrue(fileList.waitForExistence(timeout: 20), "left panel file list never appeared")

        let rows = fileList.outlineRows
        XCTAssertGreaterThan(rows.count, 1, "need at least one row besides the '..' entry")

        // Row 0 is the synthetic ".." parent entry; take the first real one.
        let targetRow = rows.element(boundBy: 1)
        targetRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(targetRow.isSelected, "clicking a row did not select it")

        // Act — click the blank area below the last row.
        clickEmptySpaceBelowRows(in: fileList)

        // Assert
        XCTAssertTrue(
            targetRow.isSelected,
            "clicking empty space deselected the row, leaving the panel with no cursor"
        )
        XCTAssertEqual(
            selectedRowCount(in: fileList),
            1,
            "panel should have exactly one selected row after clicking empty space"
        )
    }

    // MARK: - Helpers

    /// Clicks the vertical midpoint between the bottom of the last row and the
    /// bottom of the list — blank area that belongs to the list but no row.
    @MainActor
    private func clickEmptySpaceBelowRows(in fileList: XCUIElement) {
        let listFrame = fileList.frame
        let rows = fileList.outlineRows
        let lastRowMaxY = rows.element(boundBy: rows.count - 1).frame.maxY
        let emptyY = (lastRowMaxY + listFrame.maxY) / 2

        XCTAssertGreaterThan(
            listFrame.maxY - lastRowMaxY,
            24,
            "no blank area below the rows — enlarge the window or use a smaller directory"
        )

        let normalizedY = (emptyY - listFrame.minY) / listFrame.height
        fileList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: normalizedY)).click()
    }

    @MainActor
    private func selectedRowCount(in fileList: XCUIElement) -> Int {
        fileList.outlineRows.allElementsBoundByIndex.filter(\.isSelected).count
    }
}
