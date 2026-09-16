import XCTest

final class LCdrDataUITestsLaunchTests: LCdrDataUITestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    @MainActor
    func testLaunch() throws {
        let app = makeApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
