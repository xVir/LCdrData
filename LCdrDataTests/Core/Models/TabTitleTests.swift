import Testing
import Foundation
@testable import Models

@MainActor
struct TabTitleTests {
    @Test func uniqueDirectoryUsesLeafName() {
        // Arrange
        let location = BrowseLocation.directory(URL(fileURLWithPath: "/projects/v1/docs"))

        // Act
        let titles = TabTitle.labels(for: [location])

        // Assert
        #expect(titles.map(\.text) == ["docs"])
    }

    @Test func sharedLeafShowsParentDirectory() {
        // Arrange
        let locations = [
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v1/docs")),
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v2/docs"))
        ]

        // Act
        let titles = TabTitle.labels(for: locations)

        // Assert
        #expect(titles.map(\.text) == ["v1/docs", "v2/docs"])
    }

    @Test func sharedParentWalksFurtherUntilTitlesDiffer() {
        // Arrange
        let locations = [
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/a/v1/docs")),
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/b/v1/docs"))
        ]

        // Act
        let titles = TabTitle.labels(for: locations)

        // Assert
        #expect(titles.map(\.text) == ["a/v1/docs", "b/v1/docs"])
    }

    @Test func identicalDirectoriesShareOneTitle() {
        // Arrange
        let locations = [
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v1/docs")),
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v1/docs")),
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v2/docs"))
        ]

        // Act
        let titles = TabTitle.labels(for: locations)

        // Assert
        #expect(titles.map(\.text) == ["v1/docs", "v1/docs", "v2/docs"])
    }

    @Test func leafNamesThatDifferOnlyByCaseAreQualified() {
        // Arrange
        let locations = [
            BrowseLocation.directory(URL(fileURLWithPath: "/Projects/Docs")),
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/docs"))
        ]

        // Act
        let titles = TabTitle.labels(for: locations)

        // Assert
        #expect(titles.map(\.text) == ["Projects/Docs", "projects/docs"])
    }

    @Test func dotSegmentsAndTrailingSlashAreTheSameDirectory() {
        // Arrange
        let locations = [
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v1/docs")),
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v1/foo/../docs/")),
            BrowseLocation.directory(URL(fileURLWithPath: "/projects/v2/docs"))
        ]

        // Act
        let titles = TabTitle.labels(for: locations)

        // Assert
        #expect(titles.map(\.text) == ["v1/docs", "v1/docs", "v2/docs"])
    }

    @Test func archiveFolderTitleIncludesZipNameAndInternalPath() {
        // Arrange
        let container = URL(fileURLWithPath: "/projects/v2/docs/notes.zip")
        let location = BrowseLocation.zipArchive(container: container, internalPath: "a/b")

        // Act
        let titles = TabTitle.labels(for: [location])

        // Assert
        #expect(titles.map(\.text) == ["notes.zip/a/b"])
    }

    @Test func archiveRootTitleIsTheZipFileName() {
        // Arrange
        let container = URL(fileURLWithPath: "/projects/v2/docs/notes.zip")
        let location = BrowseLocation.zipArchive(container: container, internalPath: "")

        // Act
        let titles = TabTitle.labels(for: [location])

        // Assert
        #expect(titles.map(\.text) == ["notes.zip"])
    }

    @Test func collidingArchivesShowDirectoriesOutsideTheZip() {
        // Arrange
        let locations = [
            BrowseLocation.zipArchive(
                container: URL(fileURLWithPath: "/projects/v1/docs/notes.zip"),
                internalPath: "a/b"
            ),
            BrowseLocation.zipArchive(
                container: URL(fileURLWithPath: "/projects/v2/docs/notes.zip"),
                internalPath: "a/b"
            )
        ]

        // Act
        let titles = TabTitle.labels(for: locations)

        // Assert
        #expect(titles.map(\.text) == ["v1/docs/notes.zip/a/b", "v2/docs/notes.zip/a/b"])
    }

    @Test func longArchiveTitleKeepsZipNameParentAndLeaf() {
        // Arrange
        let title = TabTitle(
            components: ["notes.zip", "aaaa", "bbbb", "longParent", "leaf"],
            archiveIndex: 0
        )
        let parentForm = "notes.zip/…/longParent/leaf"

        // Act
        let fitted = TabTitle.fitted([title]) { $0.count <= parentForm.count }

        // Assert
        #expect(fitted == [parentForm])
    }

    @Test func longArchiveTitleDropsParentWhenItStillDoesNotFit() {
        // Arrange
        let title = TabTitle(
            components: ["notes.zip", "aaaa", "bbbb", "longParent", "leaf"],
            archiveIndex: 0
        )
        let leafForm = "notes.zip/…/leaf"

        // Act
        let fitted = TabTitle.fitted([title]) { $0.count <= leafForm.count }

        // Assert
        #expect(fitted == [leafForm])
    }

    @Test func shortenedArchiveTitlesKeepTheComponentThatSeparatesThem() {
        // Arrange
        let titles = [
            TabTitle(components: ["notes.zip", "a", "same", "leaf"], archiveIndex: 0),
            TabTitle(components: ["notes.zip", "b", "same", "leaf"], archiveIndex: 0)
        ]
        let limit = "notes.zip/a/…/leaf".count

        // Act
        let fitted = TabTitle.fitted(titles) { $0.count <= limit }

        // Assert
        #expect(fitted == ["notes.zip/a/…/leaf", "notes.zip/b/…/leaf"])
    }

    @Test func shortenedDirectoryTitleKeepsOutermostComponentAndLeaf() {
        // Arrange
        let title = TabTitle(components: ["v1", "mid", "docs"], archiveIndex: nil)
        let shortForm = "v1/…/docs"

        // Act
        let fitted = TabTitle.fitted([title]) { $0.count <= shortForm.count }

        // Assert
        #expect(fitted == [shortForm])
    }
}
