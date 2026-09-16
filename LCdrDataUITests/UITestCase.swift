import XCTest

class LCdrDataUITestCase: XCTestCase {

    private(set) var fixtureRoot: URL!
    private(set) var leftFixtureDirectory: URL!
    private(set) var rightFixtureDirectory: URL!
    private var application: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false

        let fileManager = FileManager.default
        fixtureRoot = fileManager.temporaryDirectory
            .appendingPathComponent("LCdrDataUITests-\(UUID().uuidString)", isDirectory: true)
        leftFixtureDirectory = fixtureRoot.appendingPathComponent("left", isDirectory: true)
        rightFixtureDirectory = fixtureRoot.appendingPathComponent("right", isDirectory: true)

        try fileManager.createDirectory(at: leftFixtureDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rightFixtureDirectory, withIntermediateDirectories: true)
        try createFixtures(in: leftFixtureDirectory, prefix: "left")
        try createFixtures(in: rightFixtureDirectory, prefix: "right")
    }

    override func tearDownWithError() throws {
        application?.terminate()
        let fileManager = FileManager.default
        if let fixtureRoot, fileManager.fileExists(atPath: fixtureRoot.path) {
            try fileManager.removeItem(at: fixtureRoot)
        }
        fixtureRoot = nil
        leftFixtureDirectory = nil
        rightFixtureDirectory = nil
    }

    @MainActor
    func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--left", leftFixtureDirectory.path,
            "--right", rightFixtureDirectory.path,
            "--no-saved-state",
        ]
        application = app
        return app
    }

    private func createFixtures(in directory: URL, prefix: String) throws {
        let fileManager = FileManager.default
        for index in 1...5 {
            let folder = directory.appendingPathComponent("\(prefix)-folder-\(index)", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("\(prefix)-file-\(index).txt")
            try Data("fixture \(index)\n".utf8).write(to: file)
        }
    }
}
