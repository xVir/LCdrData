import Testing
import Foundation
@testable import LCdrData

@MainActor
struct FileItemTests {

    @Test func initSetsAllProperties() {
        // Arrange
        let url = URL(fileURLWithPath: "/Users/test/file.txt")
        let date = Date()

        // Act
        let item = FileItem(
            url: url,
            name: "file.txt",
            isDirectory: false,
            size: 1024,
            modificationDate: date,
            creationDate: date,
            isHidden: false,
            isSymlink: false,
            permissions: 0o644
        )

        // Assert
        #expect(item.name == "file.txt")
        #expect(item.isDirectory == false)
        #expect(item.size == 1024)
        #expect(item.modificationDate == date)
        #expect(item.creationDate == date)
        #expect(item.isHidden == false)
        #expect(item.isSymlink == false)
        #expect(item.permissions == 0o644)
        #expect(item.isParentDirectory == false)
        #expect(item.url == url)
    }

    @Test func parentEntrySetsCorrectProperties() {
        // Arrange
        let directoryURL = URL(fileURLWithPath: "/Users/test/Documents")

        // Act
        let parent = FileItem.parentEntry(for: directoryURL)

        // Assert
        #expect(parent.name == "..")
        #expect(parent.isDirectory == true)
        #expect(parent.isParentDirectory == true)
        #expect(parent.url.path == "/Users/test")
    }

    @Test func defaultInitUsesDefaults() {
        // Arrange & Act
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/test"),
            name: "test",
            isDirectory: true
        )

        // Assert
        #expect(item.size == nil)
        #expect(item.modificationDate == nil)
        #expect(item.creationDate == nil)
        #expect(item.isHidden == false)
        #expect(item.isSymlink == false)
        #expect(item.permissions == 0)
        #expect(item.isParentDirectory == false)
    }

    @Test func hashableConformance() {
        // Arrange
        let item1 = FileItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "a",
            isDirectory: false
        )
        let item2 = FileItem(
            url: URL(fileURLWithPath: "/tmp/b"),
            name: "b",
            isDirectory: false
        )

        // Act
        var set: Set<FileItem> = [item1, item2]
        set.insert(item1) // duplicate — same instance, same UUID

        // Assert — item1 is the same reference so set stays at 2
        #expect(set.count == 2)
    }

    @Test func stableIDsForSameURL() {
        // Arrange & Act
        let item1 = FileItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "a",
            isDirectory: false
        )
        let item2 = FileItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "a",
            isDirectory: false
        )

        // Assert — same URL produces the same deterministic ID
        #expect(item1.id == item2.id)
    }

    @Test func differentURLsProduceDifferentIDs() {
        // Arrange & Act
        let item1 = FileItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "a",
            isDirectory: false
        )
        let item2 = FileItem(
            url: URL(fileURLWithPath: "/tmp/b"),
            name: "b",
            isDirectory: false
        )

        // Assert — different URLs produce different IDs
        #expect(item1.id != item2.id)
    }

    @Test func isNavigableDirectoryForRealDirectory() {
        // Arrange
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/folder"),
            name: "folder",
            isDirectory: true
        )

        // Assert
        #expect(item.isNavigableDirectory == true)
    }

    @Test func isNavigableDirectoryForRegularFile() {
        // Arrange
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/file.txt"),
            name: "file.txt",
            isDirectory: false
        )

        // Assert
        #expect(item.isNavigableDirectory == false)
    }

    @Test func isNavigableDirectoryForSymlinkToDirectory() {
        // Arrange — a symlink whose target is a directory
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/link-to-dir"),
            name: "link-to-dir",
            isDirectory: false,
            isSymlink: true,
            isSymlinkToDirectory: true
        )

        // Assert
        #expect(item.isNavigableDirectory == true)
    }

    @Test func isNavigableDirectoryForSymlinkToFile() {
        // Arrange — a symlink whose target is a file (or broken)
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/link-to-file"),
            name: "link-to-file",
            isDirectory: false,
            isSymlink: true,
            isSymlinkToDirectory: false
        )

        // Assert
        #expect(item.isNavigableDirectory == false)
    }

    @Test func parentEntryHasDifferentIDFromRegularDirectory() {
        // Arrange — a regular directory and a ".." entry pointing to the same URL
        let url = URL(fileURLWithPath: "/tmp")
        let regularDir = FileItem(
            url: url,
            name: "tmp",
            isDirectory: true,
            isParentDirectory: false
        )
        let parentEntry = FileItem.parentEntry(for: URL(fileURLWithPath: "/tmp/child"))

        // Assert — same URL but different identity because one is a parent entry
        #expect(regularDir.url.standardizedFileURL.path == parentEntry.url.standardizedFileURL.path)
        #expect(regularDir.id != parentEntry.id)
    }
}
