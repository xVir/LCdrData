import Testing
import Foundation
@testable import Services
@testable import Models

struct TarGzArchiveServiceTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrData-TarGzArchiveServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTarGz(at archive: URL, from directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czf", archive.path,
            "--no-mac-metadata",
            "--no-xattrs",
            "-C", directory.path,
            "."
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["COPYFILE_DISABLE"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func listRootSkipsLargeMemberBodiesAndReusesTheIndexForTheFolder() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        let folder = source.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let payload = Data(repeating: 0x61, count: 2 * 1024 * 1024)
        try payload.write(to: folder.appendingPathComponent("big.bin"))
        try Data("note".utf8).write(to: folder.appendingPathComponent("note.txt"))
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try makeTarGz(at: container, from: source)
        let service = ArchiveService()

        // Act
        let root = try await service.list(container: container, internalPath: "", showHidden: true)
        let inside = try await service.list(container: container, internalPath: "folder", showHidden: true)

        // Assert
        #expect(root.map(\.name) == ["folder"])
        #expect(root.first?.isDirectory == true)
        #expect(inside.map(\.name).sorted() == ["big.bin", "note.txt"])
        #expect(inside.first { $0.name == "big.bin" }?.size == Int64(payload.count))
    }

    @Test func listSynthesizesMissingFolderEntries() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("folder", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("contents".utf8).write(to: source.appendingPathComponent("folder/file.txt"))
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try makeTarGz(at: container, from: source)
        let service = ArchiveService()

        // Act
        let items = try await service.list(container: container, internalPath: "", showHidden: true)

        // Assert
        let folder = try #require(items.first { $0.name == "folder" })
        #expect(folder.isDirectory)
        #expect(folder.archiveInternalPath == "folder")
    }

    @Test func extractFileWritesItsUncompressedContents() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("archive contents".utf8).write(to: source.appendingPathComponent("file.txt"))
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try makeTarGz(at: container, from: source)
        let destination = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = ArchiveService()

        // Act
        try await service.extract(container: container, paths: ["file.txt"], to: destination)

        // Assert
        let extracted = destination.appendingPathComponent("file.txt")
        #expect(try String(contentsOf: extracted, encoding: .utf8) == "archive contents")
    }

    @Test func addFilePlacesItAtCurrentInternalPath() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceDirectory = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try makeTarGz(at: container, from: sourceDirectory)
        let added = temporaryDirectory.appendingPathComponent("added.txt")
        try Data("added contents".utf8).write(to: added)
        let service = ArchiveService()

        // Act
        try await service.add(container: container, internalPath: "folder", sources: [added])

        // Assert
        let items = try await service.list(container: container, internalPath: "folder", showHidden: true)
        let file = try #require(items.first { $0.name == "added.txt" })
        #expect(file.size == 14)
    }

    @Test func removeFolderDeletesItsEntirePrefix() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("folder", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("contents".utf8).write(to: source.appendingPathComponent("folder/file.txt"))
        try Data("contents".utf8).write(to: source.appendingPathComponent("keep.txt"))
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try makeTarGz(at: container, from: source)
        let service = ArchiveService()

        // Act
        try await service.remove(container: container, paths: ["folder"])

        // Assert
        let items = try await service.list(container: container, internalPath: "", showHidden: true)
        #expect(items.map(\.name).sorted() == ["keep.txt"])
    }

    @Test func createDirectoryAddsAnEmptyFolderEntry() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try makeTarGz(at: container, from: source)
        let service = ArchiveService()

        // Act
        try await service.createDirectory(container: container, internalPath: "parent", name: "child")

        // Assert
        let items = try await service.list(container: container, internalPath: "parent", showHidden: true)
        let child = try #require(items.first { $0.name == "child" })
        #expect(child.isDirectory)
    }

    @Test func renameFolderRewritesItsEntryPrefix() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("parent/old", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("contents".utf8).write(to: source.appendingPathComponent("parent/old/file.txt"))
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try makeTarGz(at: container, from: source)
        let service = ArchiveService()

        // Act
        try await service.rename(container: container, path: "parent/old", newName: "new")

        // Assert
        let items = try await service.list(container: container, internalPath: "parent", showHidden: true)
        #expect(items.map(\.name) == ["new"])
        let children = try await service.list(
            container: container,
            internalPath: "parent/new",
            showHidden: true
        )
        #expect(children.map(\.name) == ["file.txt"])
    }

    @Test func tgzExtensionUsesTheSameArchive() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("tgz".utf8).write(to: source.appendingPathComponent("note.txt"))
        let container = temporaryDirectory.appendingPathComponent("files.tgz")
        try makeTarGz(at: container, from: source)
        let service = ArchiveService()

        // Act
        let items = try await service.list(container: container, internalPath: "", showHidden: true)

        // Assert
        #expect(items.map(\.name) == ["note.txt"])
    }

    @Test func corruptArchiveCannotBeListed() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        try Data("not a tar".utf8).write(to: container)
        let service = ArchiveService()

        // Act & Assert
        await #expect(throws: ArchiveServiceError.unreadable) {
            _ = try await service.list(container: container, internalPath: "", showHidden: true)
        }
    }

    @Test func extractRejectsArchivePathTraversal() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        let writer = try TarGzWriter(url: container)
        try writer.writeFile(path: "../outside.txt", mode: 0o644, date: nil, from: source)
        try writer.finish()
        let destination = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = ArchiveService()

        // Act & Assert
        await #expect(throws: ArchiveServiceError.unsafePath("../outside.txt")) {
            try await service.extract(container: container, paths: ["../outside.txt"], to: destination)
        }
        #expect(!FileManager.default.fileExists(
            atPath: temporaryDirectory.appendingPathComponent("outside.txt").path
        ))
    }

    @Test func systemTarCanReadAnArchiveWeWrote() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("round trip".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.tar.gz")
        let writer = try TarGzWriter(url: container)
        try writer.writeFile(path: "folder/file.txt", mode: 0o644, date: nil, from: source)
        try writer.finish()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tzf", container.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let listing = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // Assert
        #expect(process.terminationStatus == 0)
        #expect(listing.contains("folder/file.txt"))
    }
}
