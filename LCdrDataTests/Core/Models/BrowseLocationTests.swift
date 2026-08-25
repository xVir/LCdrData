import Testing
import Foundation
@testable import Models

@MainActor
struct BrowseLocationTests {
    @Test func directoryParentIsContainingDirectory() {
        // Arrange
        let location = BrowseLocation.directory(URL(fileURLWithPath: "/Users/test/Documents"))

        // Act
        let parent = location.parent

        // Assert
        #expect(parent == .directory(URL(fileURLWithPath: "/Users/test", isDirectory: true)))
    }

    @Test func archiveFolderParentStaysInsideArchive() {
        // Arrange
        let container = URL(fileURLWithPath: "/Users/test/Documents/files.zip")
        let location = BrowseLocation.zipArchive(container: container, internalPath: "photos/vacation")

        // Act
        let parent = location.parent

        // Assert
        #expect(parent == .zipArchive(container: container, internalPath: "photos"))
    }

    @Test func archivePersistentDirectoryIsContainingDirectory() {
        // Arrange
        let container = URL(fileURLWithPath: "/Users/test/Documents/files.zip")
        let location = BrowseLocation.zipArchive(container: container, internalPath: "photos")

        // Act
        let persistentDirectory = location.persistentDirectory

        // Assert
        #expect(persistentDirectory.path == "/Users/test/Documents")
    }

    @Test func archiveDisplayPathIncludesInternalPath() {
        // Arrange
        let container = URL(fileURLWithPath: "/Users/test/Documents/files.zip")
        let location = BrowseLocation.zipArchive(container: container, internalPath: "photos/vacation")

        // Act
        let displayPath = location.displayPath

        // Assert
        #expect(displayPath == "/Users/test/Documents/files.zip/photos/vacation")
    }

    @Test func archiveWatchURLIsContainerFile() {
        // Arrange
        let container = URL(fileURLWithPath: "/Users/test/Documents/files.zip")
        let location = BrowseLocation.zipArchive(container: container, internalPath: "photos")

        // Act
        let watchURL = location.watchURL

        // Assert
        #expect(watchURL == container)
    }

    @Test func archiveRootParentIsContainingDirectory() {
        // Arrange
        let container = URL(fileURLWithPath: "/Users/test/Documents/files.zip")
        let location = BrowseLocation.zipArchive(container: container, internalPath: "")

        // Act
        let parent = location.parent

        // Assert
        #expect(parent.persistentDirectory.path == "/Users/test/Documents")
        #expect(parent == .directory(container.deletingLastPathComponent()))
    }
}
