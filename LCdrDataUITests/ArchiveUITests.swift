import XCTest

final class ArchiveUITests: LCdrDataUITestCase {

    /// Opening a `.tar.gz` in the left panel lists a file that exists only inside it.
    @MainActor
    func testEnteringTarGzShowsItsContents() throws {
        let fileManager = FileManager.default
        let source = fixtureRoot.appendingPathComponent("payload", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("inside archive\n".utf8).write(to: source.appendingPathComponent("inside.txt"))

        let archive = leftFixtureDirectory.appendingPathComponent("sample.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czf", archive.path,
            "--no-mac-metadata",
            "--no-xattrs",
            "-C", source.path,
            "inside.txt",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["COPYFILE_DISABLE"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let app = makeApplication()
        app.launch()

        let leftList = app.outlines["fileList.left"]
        XCTAssertTrue(leftList.waitForExistence(timeout: 20))
        // The row identifier is exposed on more than one accessibility element, so a
        // direct click of that id is ambiguous. The outline row that shows the name is not.
        let archiveRow = leftList.outlineRows
            .containing(.staticText, identifier: "sample.tar.gz")
            .element(boundBy: 0)
        XCTAssertTrue(archiveRow.waitForExistence(timeout: 5))

        archiveRow.click()
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        XCTAssertTrue(
            leftList.staticTexts["inside.txt"].waitForExistence(timeout: 10),
            "entering sample.tar.gz did not list inside.txt"
        )
        let pathBar = app.descendants(matching: .any)
            .matching(identifier: "pathBar.left")
            .firstMatch
        let path = pathBar.value as? String
        XCTAssertTrue(path?.contains("sample.tar.gz") == true, "path bar was \(path ?? "nil")")
    }

    /// F5 from inside a `.tar.gz` writes the selected member into the other panel's folder.
    @MainActor
    func testCopyFromTarGzUnpacksIntoTheOtherPanel() throws {
        try makeTarGz(named: "sample.tar.gz", in: leftFixtureDirectory, files: ["inside.txt": "inside archive\n"])

        let app = makeApplication()
        app.launch()

        let leftList = app.outlines["fileList.left"]
        let rightList = app.outlines["fileList.right"]
        XCTAssertTrue(leftList.waitForExistence(timeout: 20))
        enterArchive(named: "sample.tar.gz", in: leftList, app: app)
        row(named: "inside.txt", in: leftList).click()
        confirmCopy(in: app)

        XCTAssertTrue(
            rightList.staticTexts["inside.txt"].waitForExistence(timeout: 10),
            "copy out of sample.tar.gz did not show inside.txt in the right panel"
        )
        let unpacked = rightFixtureDirectory.appendingPathComponent("inside.txt")
        XCTAssertEqual(try String(contentsOf: unpacked, encoding: .utf8), "inside archive\n")
    }

    /// F5 from a folder into a panel that is inside a `.tar.gz` adds the file to the archive.
    @MainActor
    func testCopyIntoTarGzPacksTheSelectedFile() throws {
        try Data("pack me\n".utf8).write(to: leftFixtureDirectory.appendingPathComponent("pack-me.txt"))
        try makeTarGz(named: "sample.tar.gz", in: rightFixtureDirectory, files: ["keep.txt": "keep\n"])

        let app = makeApplication()
        app.launch()

        let leftList = app.outlines["fileList.left"]
        let rightList = app.outlines["fileList.right"]
        XCTAssertTrue(leftList.waitForExistence(timeout: 20))
        XCTAssertTrue(rightList.waitForExistence(timeout: 20))
        enterArchive(named: "sample.tar.gz", in: rightList, app: app)
        row(named: "pack-me.txt", in: leftList).click()
        confirmCopy(in: app)

        XCTAssertTrue(
            rightList.staticTexts["pack-me.txt"].waitForExistence(timeout: 10),
            "copy into sample.tar.gz did not list pack-me.txt"
        )
        let listing = try tarListing(of: rightFixtureDirectory.appendingPathComponent("sample.tar.gz"))
        XCTAssertTrue(listing.contains("pack-me.txt"), "archive listing was \(listing)")
        XCTAssertTrue(listing.contains("keep.txt"), "packing removed keep.txt; listing was \(listing)")
    }

    private func makeTarGz(named name: String, in directory: URL, files: [String: String]) throws {
        let fileManager = FileManager.default
        let source = fixtureRoot.appendingPathComponent("payload-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        for (fileName, contents) in files {
            try Data(contents.utf8).write(to: source.appendingPathComponent(fileName))
        }

        let archive = directory.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czf", archive.path,
            "--no-mac-metadata",
            "--no-xattrs",
            "-C", source.path,
        ] + files.keys.sorted()
        var environment = ProcessInfo.processInfo.environment
        environment["COPYFILE_DISABLE"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func tarListing(of archive: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tzf", archive.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @MainActor
    private func enterArchive(named name: String, in list: XCUIElement, app: XCUIApplication) {
        let archiveRow = row(named: name, in: list)
        XCTAssertTrue(archiveRow.waitForExistence(timeout: 5))
        archiveRow.click()
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
    }

    @MainActor
    private func row(named name: String, in list: XCUIElement) -> XCUIElement {
        list.outlineRows.containing(.staticText, identifier: name).element(boundBy: 0)
    }

    @MainActor
    private func confirmCopy(in app: XCUIApplication) {
        let copy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "F5")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "F5 command button not found")
        copy.click()

        let dialogConfirm = app.dialogs.buttons["Confirm"]
        let sheetConfirm = app.sheets.buttons["Confirm"]
        if dialogConfirm.waitForExistence(timeout: 5) {
            dialogConfirm.click()
        } else {
            XCTAssertTrue(sheetConfirm.waitForExistence(timeout: 2), "copy confirmation did not appear")
            sheetConfirm.click()
        }
    }
}
