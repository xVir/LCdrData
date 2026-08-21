import Testing
import Foundation
@testable import Core

/// Stands in for the account database so the expectations don't depend on the
/// account the suite happens to run as.
nonisolated struct StubHomeDirectoryProvider: HomeDirectoryProviding {
    let homeDirectory: URL
}

struct TildePathExpanderTests {

    private static let home = URL(fileURLWithPath: "/Users/dskachkov", isDirectory: true)

    private static func makeExpander() -> TildePathExpander {
        TildePathExpander(home: StubHomeDirectoryProvider(homeDirectory: home))
    }

    @Test func expandsTildeToTheRealHomeNotTheSandboxContainer() {
        // Arrange
        let expander = Self.makeExpander()

        // Act
        let url = expander.expand("~/Downloads")

        // Assert
        #expect(url.path == "/Users/dskachkov/Downloads")
    }

    @Test func expandsMultiComponentPath() {
        // Arrange
        let expander = Self.makeExpander()

        // Act
        let url = expander.expand("~/Projects/personal/LCdrData")

        // Assert
        #expect(url.path == "/Users/dskachkov/Projects/personal/LCdrData")
    }

    @Test func bareTildeIsTheHomeDirectory() {
        // Arrange
        let expander = Self.makeExpander()

        // Act & Assert
        #expect(expander.expand("~").path == "/Users/dskachkov")
        #expect(expander.expand("~/").path == "/Users/dskachkov")
    }

    @Test func absolutePathPassesThroughUnchanged() {
        // Arrange
        let expander = Self.makeExpander()

        // Act
        let url = expander.expand("/Volumes/Backup/Photos")

        // Assert
        #expect(url.path == "/Volumes/Backup/Photos")
    }

    @Test func surroundingWhitespaceIsIgnored() {
        // Arrange
        let expander = Self.makeExpander()

        // Act
        let url = expander.expand("  ~/Projects  ")

        // Assert
        #expect(url.path == "/Users/dskachkov/Projects")
    }

    @Test func tildeInsideThePathIsNotTreatedAsHome() {
        // Arrange
        let expander = Self.makeExpander()

        // Act
        let url = expander.expand("/tmp/~backup")

        // Assert
        #expect(url.path == "/tmp/~backup")
    }

    @Test func accountProviderReportsHomeOutsideTheSandboxContainer() {
        // Arrange
        let provider = AccountHomeDirectoryProvider()

        // Act
        let home = provider.homeDirectory

        // Assert — the whole point: never the app's container.
        #expect(!home.path.contains("/Library/Containers/"))
        #expect(home.path.hasPrefix("/Users/") || home.path.hasPrefix("/var/"))
    }
}
