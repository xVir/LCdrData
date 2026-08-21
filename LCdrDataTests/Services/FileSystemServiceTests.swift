import Testing
import Foundation
@testable import Services
@testable import Models

@MainActor
struct FileSystemServiceTests {

    /// Builds a fresh temp directory for an isolated test, returning its URL
    /// and a cleanup closure to call from a `defer`.
    private static func makeTempDirectory() throws -> (URL, () -> Void) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("LCdrData-FileSystemServiceTests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let cleanup: () -> Void = { try? fm.removeItem(at: dir) }
        return (dir, cleanup)
    }

    @Test func listDirectoryClassifiesRegularEntries() async throws {
        // Arrange
        let (root, cleanup) = try Self.makeTempDirectory()
        defer { cleanup() }

        let fm = FileManager.default
        let realDir = root.appendingPathComponent("real_dir")
        let realFile = root.appendingPathComponent("real_file.txt")
        try fm.createDirectory(at: realDir, withIntermediateDirectories: false)
        try Data("hello".utf8).write(to: realFile)

        let service = FileSystemService()

        // Act
        let items = try await service.listDirectory(at: root, showHidden: false)

        // Assert
        let dirItem = try #require(items.first { $0.name == "real_dir" })
        let fileItem = try #require(items.first { $0.name == "real_file.txt" })

        #expect(dirItem.isDirectory == true)
        #expect(dirItem.isSymlink == false)
        #expect(dirItem.isSymlinkToDirectory == false)
        #expect(dirItem.isNavigableDirectory == true)

        #expect(fileItem.isDirectory == false)
        #expect(fileItem.isSymlink == false)
        #expect(fileItem.isSymlinkToDirectory == false)
        #expect(fileItem.isNavigableDirectory == false)
    }

    @Test func listDirectoryFlagsSymlinkToDirectory() async throws {
        // Arrange
        let (root, cleanup) = try Self.makeTempDirectory()
        defer { cleanup() }

        let fm = FileManager.default
        let target = root.appendingPathComponent("target_dir")
        try fm.createDirectory(at: target, withIntermediateDirectories: false)

        let link = root.appendingPathComponent("link_to_dir")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)

        let service = FileSystemService()

        // Act
        let items = try await service.listDirectory(at: root, showHidden: false)

        // Assert
        let linkItem = try #require(items.first { $0.name == "link_to_dir" })
        #expect(linkItem.isSymlink == true)
        #expect(linkItem.isDirectory == false)
        #expect(linkItem.isSymlinkToDirectory == true)
        #expect(linkItem.isNavigableDirectory == true)
    }

    @Test func listDirectoryFlagsSymlinkToFile() async throws {
        // Arrange
        let (root, cleanup) = try Self.makeTempDirectory()
        defer { cleanup() }

        let fm = FileManager.default
        let target = root.appendingPathComponent("target_file.txt")
        try Data("hello".utf8).write(to: target)

        let link = root.appendingPathComponent("link_to_file")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)

        let service = FileSystemService()

        // Act
        let items = try await service.listDirectory(at: root, showHidden: false)

        // Assert
        let linkItem = try #require(items.first { $0.name == "link_to_file" })
        #expect(linkItem.isSymlink == true)
        #expect(linkItem.isDirectory == false)
        #expect(linkItem.isSymlinkToDirectory == false)
        #expect(linkItem.isNavigableDirectory == false)
    }

    @Test func listDirectoryHandlesBrokenSymlink() async throws {
        // Arrange — a symlink whose target does not exist.
        let (root, cleanup) = try Self.makeTempDirectory()
        defer { cleanup() }

        let fm = FileManager.default
        let missing = root.appendingPathComponent("does_not_exist")
        let link = root.appendingPathComponent("broken_link")
        try fm.createSymbolicLink(at: link, withDestinationURL: missing)

        let service = FileSystemService()

        // Act
        let items = try await service.listDirectory(at: root, showHidden: false)

        // Assert — the link should still appear; navigation must NOT trigger.
        let linkItem = try #require(items.first { $0.name == "broken_link" })
        #expect(linkItem.isSymlink == true)
        #expect(linkItem.isSymlinkToDirectory == false)
        #expect(linkItem.isNavigableDirectory == false)
    }
}
