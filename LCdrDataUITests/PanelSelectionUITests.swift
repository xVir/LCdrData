import XCTest

final class PanelSelectionUITests: LCdrDataUITestCase {

    /// Clicking the blank area below the last row must not leave the panel
    /// without a selected row — the cursor stays on the row it was on.
    @MainActor
    func testClickingEmptySpaceKeepsRowSelected() throws {
        // Arrange
        let app = makeApplication()
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

    /// A secondary click on a row that is not in the current multi-selection
    /// must collapse the selection to that row.
    @MainActor
    func testSecondaryClickOutsideSelectionSelectsOnlyThatRow() throws {
        // Arrange
        let app = makeApplication()
        app.launch()

        let fileList = app.outlines["fileList.left"]
        XCTAssertTrue(fileList.waitForExistence(timeout: 20), "left panel file list never appeared")

        let rows = fileList.outlineRows
        XCTAssertGreaterThan(rows.count, 3, "need at least three real rows besides '..'")

        let first = rows.element(boundBy: 1)
        let second = rows.element(boundBy: 2)
        let third = rows.element(boundBy: 3)

        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCUIElement.perform(withKeyModifiers: .command) {
            second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        XCTAssertTrue(first.isSelected, "first row should stay selected after ⌘-click")
        XCTAssertTrue(second.isSelected, "⌘-click should add the second row")
        XCTAssertFalse(third.isSelected, "third row should still be unselected")

        // Act
        third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()

        // Assert
        XCTAssertTrue(third.isSelected, "secondary click outside the selection should select that row")
        XCTAssertFalse(first.isSelected, "previous selection should be cleared")
        XCTAssertFalse(second.isSelected, "previous selection should be cleared")
        XCTAssertEqual(
            selectedRowCount(in: fileList),
            1,
            "only the secondary-clicked row should be selected"
        )
    }

    /// A secondary click on a row that is already part of a multi-selection
    /// must leave the whole selection in place.
    @MainActor
    func testSecondaryClickInsideSelectionKeepsSelection() throws {
        // Arrange
        let app = makeApplication()
        app.launch()

        let fileList = app.outlines["fileList.left"]
        XCTAssertTrue(fileList.waitForExistence(timeout: 20), "left panel file list never appeared")

        let rows = fileList.outlineRows
        XCTAssertGreaterThan(rows.count, 2, "need at least two real rows besides '..'")

        let first = rows.element(boundBy: 1)
        let second = rows.element(boundBy: 2)

        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCUIElement.perform(withKeyModifiers: .command) {
            second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        XCTAssertTrue(first.isSelected)
        XCTAssertTrue(second.isSelected)

        // Act
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()

        // Assert
        XCTAssertTrue(first.isSelected, "in-selection secondary click should keep the other selected rows")
        XCTAssertTrue(second.isSelected, "the clicked row should remain selected")
        XCTAssertEqual(
            selectedRowCount(in: fileList),
            2,
            "multi-selection should be unchanged after secondary-clicking inside it"
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
