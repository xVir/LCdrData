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
