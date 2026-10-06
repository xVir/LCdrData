import Foundation
import Testing
@testable import Services
@testable import Models

@MainActor
struct ConfigurationServiceTests {

    private let sampleDefaultKDL = """
    panel {
        show-hidden-files #false
        sort-by name
        sort-ascending #true
    }

    appearance {
        font-size 13
        date-format "yyyy-MM-dd HH:mm"
    }

    bookmarks {
        - "Projects|~/Projects"
        - "Downloads|~/Downloads"
    }

    editor {
        default-app "com.apple.TextEdit"
        open-folders #false
    }

    operations {
        max-active 3
    }

    """

    private func makeService(tempDir: URL) -> ConfigurationService {
        ConfigurationService(
            bundle: Bundle.main,
            fileManager: .default,
            configDirectory: tempDir,
            defaultKDLTextOverride: sampleDefaultKDL
        )
    }

    @Test func parsesPanelSortAndHiddenFromKDL() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        try svc.load()

        #expect(svc.current.panelShowHiddenFiles == false)
        #expect(svc.current.panelSortColumn == .name)
        #expect(svc.current.panelSortAscending == true)
    }

    @Test func editorOpenFoldersDefaultsToFalseAndParsesFromKDL() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        try svc.load()

        #expect(svc.current.editorOpenFolders == false)

        try svc.apply(fromUserKDL: """
        editor {
            open-folders #true
        }

        """)

        #expect(svc.current.editorOpenFolders == true)
    }

    @Test func operationsMaxActiveDefaultsToThreeAndParsesFromKDL() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        try svc.load()

        #expect(svc.current.operationsMaxActive == 3)

        try svc.apply(fromUserKDL: """
        operations {
            max-active 5
        }

        """)

        #expect(svc.current.operationsMaxActive == 5)
    }

    @Test func operationsMaxActiveIgnoresValuesBelowOne() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        try svc.load()

        try svc.apply(fromUserKDL: """
        operations {
            max-active 0
        }

        """)

        #expect(svc.current.operationsMaxActive == 3)
    }

    @Test func applyUserKDLMergesOntoDefaults() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        let userKDL = """
        panel {
            sort-by size
            sort-ascending #false
        }
        """
        try svc.apply(fromUserKDL: userKDL)

        #expect(svc.current.panelSortColumn == .size)
        #expect(svc.current.panelSortAscending == false)
        #expect(svc.current.panelShowHiddenFiles == false)

        let onDisk = try String(contentsOf: svc.userConfigFileURL, encoding: .utf8)
        #expect(onDisk.contains("sort-by"))
    }

    @Test func terminalDefaultsToMacOSTerminalAndParsesFromKDL() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        try svc.load()

        #expect(svc.current.terminalDefaultAppBundleID == "com.apple.Terminal")

        try svc.apply(fromUserKDL: """
        terminal {
            // Example configuration for the Ghostty terminal app:
            // default-app "com.mitchellh.ghostty"
            default-app "com.mitchellh.ghostty"
        }

        """)

        #expect(svc.current.terminalDefaultAppBundleID == "com.mitchellh.ghostty")
    }

    @Test func terminalIgnoresABlankDefaultApp() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        try svc.load()

        try svc.apply(fromUserKDL: """
        terminal {
            default-app ""
        }

        """)

        #expect(svc.current.terminalDefaultAppBundleID == "com.apple.Terminal")
    }

    @Test func bundledDefaultsNameMacOSTerminalAndDocumentGhostty() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let reader = ConfigurationService(
            bundle: Bundle.main,
            fileManager: .default,
            configDirectory: tmp,
            defaultKDLTextOverride: nil
        )
        let text = try reader.defaultKDLText()
        #expect(text.contains("default-app \"com.apple.Terminal\""))
        #expect(text.contains("Example configuration for the Ghostty terminal app:"))
        #expect(text.contains("com.mitchellh.ghostty"))

        let applying = ConfigurationService(
            bundle: Bundle.main,
            fileManager: .default,
            configDirectory: tmp,
            defaultKDLTextOverride: text
        )
        try applying.load()
        #expect(applying.current.terminalDefaultAppBundleID == "com.apple.Terminal")
    }

    @Test func applyInvalidKDLPthrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrDataCfgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc = makeService(tempDir: tmp)
        #expect(throws: ConfigurationServiceError.self) {
            try svc.apply(fromUserKDL: "this is not { valid kdl")
        }
    }
}
