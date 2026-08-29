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
        #expect(FileFormatter.formatSize(0) == "0b")
    }

    @Test func formatSizeBytes() {
        #expect(FileFormatter.formatSize(500) == "500b")
    }

    @Test func formatSizeKilobytes() {
        #expect(FileFormatter.formatSize(1_000) == "1Kb")
        #expect(FileFormatter.formatSize(1_500) == "1.5Kb")
    }

    @Test func formatSizeMegabytes() {
        #expect(FileFormatter.formatSize(5_000_000) == "5Mb")
        #expect(FileFormatter.formatSize(4_200_000) == "4.2Mb")
    }

    @Test func formatSizeLargerUnits() {
        #expect(FileFormatter.formatSize(2_000_000_000) == "2Gb")
        #expect(FileFormatter.formatSize(3_500_000_000_000) == "3.5Tb")
    }

    @Test func formatSizeRoundsUpToNextUnit() {
        #expect(FileFormatter.formatSize(999_999) == "1Mb")
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

    @Test func kindForArchiveMemberUsesMemberExtension() {
        let item = FileItem(
            archiveContainer: URL(fileURLWithPath: "/tmp/files.zip"),
            internalPath: "folder/file.txt",
            name: "file.txt",
            isDirectory: false
        )
        #expect(FileFormatter.kind(for: item) == "TXT")
    }
}
