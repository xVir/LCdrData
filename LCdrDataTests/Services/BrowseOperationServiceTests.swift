import Testing
import Foundation
import ZIPFoundation
@testable import Models
@testable import Services

struct BrowseOperationServiceTests {
    @Test func copyFromDirectoryIntoArchiveAddsSelectedFile() async throws {
        // Arrange
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrData-BrowseOperationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("contents".utf8).write(to: sourceURL)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        _ = try Archive(url: container, accessMode: .create)
        let service = BrowseOperationService(
            fileService: FileOperationService(),
            archiveService: ArchiveService()
        )
        let item = FileItem(url: sourceURL, name: "source.txt", isDirectory: false)

        // Act
        try await service.copy(
            items: [item],
            from: .directory(temporaryDirectory),
            to: .zipArchive(container: container, internalPath: "folder"),
            onProgress: { _ in },
            onConflict: { _ in .skip }
        )

        // Assert
        let archive = try Archive(url: container, accessMode: .read)
        #expect(archive["folder/source.txt"] != nil)
    }

    @Test func archiveConflictCanRenameIncomingFile() async throws {
        // Arrange
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrData-BrowseOperationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceDirectory = temporaryDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent("file.txt")
        try Data("new".utf8).write(to: sourceURL)
        let existingURL = temporaryDirectory.appendingPathComponent("existing.txt")
        try Data("old".utf8).write(to: existingURL)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "file.txt", fileURL: existingURL)
        let service = BrowseOperationService()
        let item = FileItem(url: sourceURL, name: "file.txt", isDirectory: false)

        // Act
        try await service.copy(
            items: [item],
            from: .directory(sourceDirectory),
            to: .zipArchive(container: container, internalPath: ""),
            onProgress: { _ in },
            onConflict: { _ in .rename(newName: "file copy.txt") }
        )

        // Assert
        let updatedArchive = try Archive(url: container, accessMode: .read)
        #expect(updatedArchive["file.txt"] != nil)
        #expect(updatedArchive["file copy.txt"] != nil)
    }

    @Test func skippedArchiveMoveDoesNotRemoveSourceEntry() async throws {
        // Arrange
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrData-BrowseOperationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("source.txt")
        try Data("archive".utf8).write(to: sourceURL)
        let container = temporaryDirectory.appendingPathComponent("files.zip")
        let archive = try Archive(url: container, accessMode: .create)
        try archive.addEntry(with: "source.txt", fileURL: sourceURL)
        let destination = temporaryDirectory.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: destination.appendingPathComponent("source.txt"))
        let item = FileItem(
            archiveContainer: container,
            internalPath: "source.txt",
            name: "source.txt",
            isDirectory: false
        )
        let service = BrowseOperationService()

        // Act
        try await service.move(
            items: [item],
            from: .zipArchive(container: container, internalPath: ""),
            to: .directory(destination),
            onProgress: { _ in },
            onConflict: { _ in .skip }
        )

        // Assert
        let updatedArchive = try Archive(url: container, accessMode: .read)
        #expect(updatedArchive["source.txt"] != nil)
        #expect(
            try String(contentsOf: destination.appendingPathComponent("source.txt"), encoding: .utf8)
                == "existing"
        )
    }
}
