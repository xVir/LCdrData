import XCTest

final class TabTitleUITests: LCdrDataUITestCase {

    @MainActor
    func testTabTitleShowsParentWhenAnotherPanelHasTheSameLeaf() throws {
        let fileManager = FileManager.default
        let v1 = fixtureRoot.appendingPathComponent("v1/docs", isDirectory: true)
        let v2 = fixtureRoot.appendingPathComponent("v2/docs", isDirectory: true)
        try fileManager.createDirectory(at: v1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: v2, withIntermediateDirectories: true)

        let app = makeApplication()
        app.launchArguments = [
            "--left", v1.path,
            "--right", v2.path,
            "--no-saved-state",
        ]
        app.launch()

        XCTAssertTrue(app.outlines["fileList.left"].waitForExistence(timeout: 20))

        // A panel shows its strip only once it has a second tab. The right panel's
        // single hidden tab still counts, so the left titles pick up `v1`.
        app.typeKey("t", modifierFlags: .command)

        let leftTab = app.buttons["tab.left.0"]
        XCTAssertTrue(leftTab.waitForExistence(timeout: 5))
        XCTAssertEqual(leftTab.label, "v1/docs")
        XCTAssertEqual(app.buttons["tab.left.1"].label, "v1/docs")

        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        app.typeKey("t", modifierFlags: .command)

        let rightTab = app.buttons["tab.right.0"]
        XCTAssertTrue(rightTab.waitForExistence(timeout: 5))
        XCTAssertEqual(rightTab.label, "v2/docs")
    }
}
