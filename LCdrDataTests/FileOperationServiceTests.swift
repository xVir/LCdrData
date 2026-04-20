//
//  FileOperationServiceTests.swift
//  LCdrDataTests
//
//  Created by Dima Skachkov on 20.04.2026.
//

import Testing
import Foundation
@testable import LCdrData

@MainActor
struct FileOperationServiceTests {

    // MARK: - Helpers

    /// Creates a temporary directory for each test.
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    /// Creates a test file with the given name and content in the directory.
    private func createFile(
        named name: String,
        content: String = "test",
        in directory: URL
    ) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Cleans up a temporary directory.
    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Copy Tests

    @Test func copyFileToDestination() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        let fileURL = try createFile(named: "test.txt", content: "hello", in: sourceDir)
        let service = FileOperationService()

        var progressUpdates: [FileOperationProgress] = []
        try await service.copy(
            sources: [fileURL],
            to: destDir,
            onProgress: { progress in progressUpdates.append(progress) },
            onConflict: { _ in .skip }
        )

        // Verify file was copied
        let copiedFile = destDir.appendingPathComponent("test.txt")
        #expect(FileManager.default.fileExists(atPath: copiedFile.path))
        let content = try String(contentsOf: copiedFile, encoding: .utf8)
        #expect(content == "hello")

        // Verify progress was reported
        #expect(progressUpdates.count == 1)
        #expect(progressUpdates[0].completedItems == 1)
        #expect(progressUpdates[0].totalItems == 1)

        // Verify original still exists
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func copyMultipleFiles() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        let file1 = try createFile(named: "a.txt", content: "aaa", in: sourceDir)
        let file2 = try createFile(named: "b.txt", content: "bbb", in: sourceDir)
        let service = FileOperationService()

        var progressUpdates: [FileOperationProgress] = []
        try await service.copy(
            sources: [file1, file2],
            to: destDir,
            onProgress: { progress in progressUpdates.append(progress) },
            onConflict: { _ in .skip }
        )

        #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.txt").path))
        #expect(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("b.txt").path))
        #expect(progressUpdates.count == 2)
        #expect(progressUpdates[1].completedItems == 2)
    }

    @Test func copyWithConflictOverwrite() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        let _ = try createFile(named: "test.txt", content: "new content", in: sourceDir)
        let _ = try createFile(named: "test.txt", content: "old content", in: destDir)
        let service = FileOperationService()

        try await service.copy(
            sources: [sourceDir.appendingPathComponent("test.txt")],
            to: destDir,
            onProgress: { _ in },
            onConflict: { _ in .overwrite }
        )

        let content = try String(
            contentsOf: destDir.appendingPathComponent("test.txt"),
            encoding: .utf8
        )
        #expect(content == "new content")
    }

    @Test func copyWithConflictSkip() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        let _ = try createFile(named: "test.txt", content: "new", in: sourceDir)
        let _ = try createFile(named: "test.txt", content: "old", in: destDir)
        let service = FileOperationService()

        try await service.copy(
            sources: [sourceDir.appendingPathComponent("test.txt")],
            to: destDir,
            onProgress: { _ in },
            onConflict: { _ in .skip }
        )

        // Original content should remain
        let content = try String(
            contentsOf: destDir.appendingPathComponent("test.txt"),
            encoding: .utf8
        )
        #expect(content == "old")
    }

    @Test func copyWithConflictRename() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        let _ = try createFile(named: "test.txt", content: "new", in: sourceDir)
        let _ = try createFile(named: "test.txt", content: "old", in: destDir)
        let service = FileOperationService()

        try await service.copy(
            sources: [sourceDir.appendingPathComponent("test.txt")],
            to: destDir,
            onProgress: { _ in },
            onConflict: { _ in .rename(newName: "test_copy.txt") }
        )

        // Original should remain unchanged
        let oldContent = try String(
            contentsOf: destDir.appendingPathComponent("test.txt"),
            encoding: .utf8
        )
        #expect(oldContent == "old")

        // Renamed copy should exist
        let newContent = try String(
            contentsOf: destDir.appendingPathComponent("test_copy.txt"),
            encoding: .utf8
        )
        #expect(newContent == "new")
    }

    // MARK: - Move Tests

    @Test func moveFileToDestination() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        let fileURL = try createFile(named: "moveme.txt", content: "data", in: sourceDir)
        let service = FileOperationService()

        try await service.move(
            sources: [fileURL],
            to: destDir,
            onProgress: { _ in },
            onConflict: { _ in .skip }
        )

        // Verify file was moved
        let movedFile = destDir.appendingPathComponent("moveme.txt")
        #expect(FileManager.default.fileExists(atPath: movedFile.path))
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func moveWithConflictOverwrite() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        let fileURL = try createFile(named: "test.txt", content: "new", in: sourceDir)
        let _ = try createFile(named: "test.txt", content: "old", in: destDir)
        let service = FileOperationService()

        try await service.move(
            sources: [fileURL],
            to: destDir,
            onProgress: { _ in },
            onConflict: { _ in .overwrite }
        )

        let content = try String(
            contentsOf: destDir.appendingPathComponent("test.txt"),
            encoding: .utf8
        )
        #expect(content == "new")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Trash Tests

    @Test func trashFile() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let fileURL = try createFile(named: "trash_me.txt", in: dir)
        let service = FileOperationService()

        let trashedURLs = try await service.trash(items: [fileURL])

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(trashedURLs.count == 1)
    }

    // MARK: - Create Folder Tests

    @Test func createFolder() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let service = FileOperationService()
        let folderURL = try await service.createFolder(in: dir, name: "NewFolder")

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
        #expect(folderURL.lastPathComponent == "NewFolder")
    }

    @Test func createFolderAlreadyExists() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Create the folder first
        let folderURL = dir.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)

        let service = FileOperationService()

        do {
            _ = try await service.createFolder(in: dir, name: "Existing")
            #expect(Bool(false), "Should have thrown")
        } catch let error as FileOperationError {
            #expect(error == .itemAlreadyExists(name: "Existing"))
        }
    }

    // MARK: - Rename Tests

    @Test func renameFile() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let fileURL = try createFile(named: "old_name.txt", content: "data", in: dir)
        let service = FileOperationService()

        let newURL = try await service.rename(item: fileURL, to: "new_name.txt")

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(FileManager.default.fileExists(atPath: newURL.path))
        #expect(newURL.lastPathComponent == "new_name.txt")
        let content = try String(contentsOf: newURL, encoding: .utf8)
        #expect(content == "data")
    }

    @Test func renameToExistingNameFails() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let _ = try createFile(named: "file_a.txt", in: dir)
        let fileB = try createFile(named: "file_b.txt", in: dir)
        let service = FileOperationService()

        do {
            _ = try await service.rename(item: fileB, to: "file_a.txt")
            #expect(Bool(false), "Should have thrown")
        } catch let error as FileOperationError {
            #expect(error == .itemAlreadyExists(name: "file_a.txt"))
        }
    }

    // MARK: - Copy Directory Tests

    @Test func copyDirectoryToDestination() async throws {
        let sourceDir = try makeTempDir()
        let destDir = try makeTempDir()
        defer {
            cleanup(sourceDir)
            cleanup(destDir)
        }

        // Create a subdirectory with a file inside
        let subDir = sourceDir.appendingPathComponent("mydir", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: false)
        let _ = try createFile(named: "inside.txt", content: "nested", in: subDir)

        let service = FileOperationService()

        try await service.copy(
            sources: [subDir],
            to: destDir,
            onProgress: { _ in },
            onConflict: { _ in .skip }
        )

        let copiedDir = destDir.appendingPathComponent("mydir")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: copiedDir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)

        let innerFile = copiedDir.appendingPathComponent("inside.txt")
        let content = try String(contentsOf: innerFile, encoding: .utf8)
        #expect(content == "nested")
    }
}
