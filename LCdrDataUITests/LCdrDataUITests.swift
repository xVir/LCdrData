import XCTest

final class LCdrDataUITests: LCdrDataUITestCase {

    @MainActor
    func testMainWindowLaunches() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApplication().launch()
        }
    }
}
