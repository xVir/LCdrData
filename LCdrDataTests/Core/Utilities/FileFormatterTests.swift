import Testing
import Foundation
@testable import Models
@testable import Formatting

@MainActor
struct FileFormatterTests {

    // MARK: - Size Formatting

    @Test func formatSizeNilReturnsDash() {
        #expect(FileFormatter.formatSize(nil) == "--")
    }

    @Test func formatSizeZero() {
        let result = FileFormatter.formatSize(0)
        #expect(result == "Zero KB")
    }

    @Test func formatSizeBytes() {
        let result = FileFormatter.formatSize(500)
        // ByteCountFormatter may return "500 bytes" or similar
        #expect(!result.isEmpty)
        #expect(result != "--")
    }

    @Test func formatSizeMegabytes() {
        let result = FileFormatter.formatSize(5_000_000)
        #expect(result.contains("MB") || result.contains("5"))
    }

    // MARK: - Date Formatting

    @Test func formatDateNilReturnsDash() {
        #expect(FileFormatter.formatDate(nil) == "--")
    }

    @Test func formatDateReturnsFormattedString() {
        // Arrange
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = DateComponents(year: 2026, month: 4, day: 2, hour: 14, minute: 30)
        let date = calendar.date(from: components)!

        // Act
        let result = FileFormatter.formatDate(date)

        // Assert
        #expect(result.contains("2026"))
        #expect(result.contains("04"))
        #expect(result.contains("02"))
    }

    // MARK: - Kind

    @Test func kindForDirectory() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/folder"),
            name: "folder",
            isDirectory: true
        )
        #expect(FileFormatter.kind(for: item) == "Folder")
    }

    @Test func kindForParentDirectory() {
        let item = FileItem.parentEntry(for: URL(fileURLWithPath: "/tmp"))
        #expect(FileFormatter.kind(for: item) == "Parent")
    }

    @Test func kindForSymlink() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/link"),
            name: "link",
            isDirectory: false,
            isSymlink: true
        )
        #expect(FileFormatter.kind(for: item) == "Alias")
    }

    @Test func kindForFileWithExtension() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/file.pdf"),
            name: "file.pdf",
            isDirectory: false
        )
        #expect(FileFormatter.kind(for: item) == "PDF")
    }

    @Test func kindForFileWithoutExtension() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/Makefile"),
            name: "Makefile",
            isDirectory: false
        )
        #expect(FileFormatter.kind(for: item) == "Document")
    }
}
