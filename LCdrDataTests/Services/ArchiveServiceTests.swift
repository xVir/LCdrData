import Testing
import Foundation
import ZIPFoundation
@testable import Services
@testable import Models

struct ArchiveServiceTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrData-ArchiveServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func listSynthesizesMissingFolderEntries() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("file.txt")
        try Data("contents".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "folder/file.txt", fileURL: source)
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
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("archive contents".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "folder/file.txt", fileURL: source)
        let destination = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = ArchiveService()

        // Act
        try await service.extract(container: container, paths: ["folder/file.txt"], to: destination)

        // Assert
        let extracted = destination.appendingPathComponent("file.txt")
        #expect(try String(contentsOf: extracted, encoding: .utf8) == "archive contents")
    }

    @Test func addFilePlacesItAtCurrentInternalPath() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        _ = try Archive(url: container, accessMode: .create)
        let source = temporaryDirectory.appendingPathComponent("added.txt")
        try Data("added contents".utf8).write(to: source)
        let service = ArchiveService()

        // Act
        try await service.add(container: container, internalPath: "folder", sources: [source])

        // Assert
        let items = try await service.list(container: container, internalPath: "folder", showHidden: true)
        let added = try #require(items.first { $0.name == "added.txt" })
        #expect(added.size == 14)
    }

    @Test func removeFolderDeletesItsEntirePrefix() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "folder/file.txt", fileURL: source)
        try archive.addEntry(with: "keep.txt", fileURL: source)
        let service = ArchiveService()

        // Act
        try await service.remove(container: container, paths: ["folder"])

        // Assert
        let items = try await service.list(container: container, internalPath: "", showHidden: true)
        #expect(items.map(\.name) == ["keep.txt"])
    }

    @Test func createDirectoryAddsAnEmptyFolderEntry() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        _ = try Archive(url: container, accessMode: .create)
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
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "parent/old/file.txt", fileURL: source)
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

    @Test func nonWritableArchiveIsReportedReadOnly() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        _ = try Archive(url: container, accessMode: .create)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: container.path)
        let service = ArchiveService()

        // Act
        let isWritable = await service.isWritable(container: container)

        // Assert
        #expect(isWritable == false)
    }

    @Test func addToReadOnlyArchiveFailsWithNotWritable() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        _ = try Archive(url: container, accessMode: .create)
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: container.path)
        let service = ArchiveService()

        // Act & Assert
        await #expect(throws: ArchiveServiceError.notWritable) {
            try await service.add(container: container, internalPath: "", sources: [source])
        }
    }

    @Test func corruptArchiveCannotBeListed() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        try Data("not a zip".utf8).write(to: container)
        let service = ArchiveService()

        // Act & Assert
        await #expect(throws: ArchiveServiceError.unreadable) {
            _ = try await service.list(container: container, internalPath: "", showHidden: true)
        }
    }

    @Test func extractFolderPreservesItsTree() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("nested contents".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "folder/nested/file.txt", fileURL: source)
        let destination = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = ArchiveService()

        // Act
        try await service.extract(container: container, paths: ["folder"], to: destination)

        // Assert
        let extracted = destination.appendingPathComponent("folder/nested/file.txt")
        #expect(try String(contentsOf: extracted, encoding: .utf8) == "nested contents")
    }

    @Test func extractRejectsArchivePathTraversal() async throws {
        // Arrange
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let source = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: source)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "../outside.txt", fileURL: source)
        let destination = temporaryDirectory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = ArchiveService()

        // Act & Assert
        await #expect(throws: ArchiveServiceError.unsafePath("../outside.txt")) {
            try await service.extract(
                container: container,
                paths: ["../outside.txt"],
                to: destination
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: temporaryDirectory.appendingPathComponent("outside.txt").path
        ))
    }
}
