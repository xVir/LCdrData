import Testing
import Foundation
@testable import Models
@testable import Services
@testable import ViewModels

// MARK: - Fake File Opening Service

/// Records what F4 asked to open, and with which application, without
/// launching anything.
nonisolated final class FakeFileOpeningService: FileOpeningServiceProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private(set) var openedURLs: [URL] = []
    private(set) var requestedBundleIDs: [String?] = []

    func open(_ url: URL, preferredApplicationBundleID bundleID: String?) async {
        lock.withLock {
            openedURLs.append(url)
            requestedBundleIDs.append(bundleID)
        }
    }
}

// MARK: - Tests

@MainActor
struct PanelViewModelEditorTests {

    private func textFile() -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/notes.txt"),
            name: "notes.txt",
            isDirectory: false,
            size: 12,
            modificationDate: Date(timeIntervalSince1970: 1000)
        )
    }

    @Test func editOpensSelectedFileWithConfiguredEditor() async {
        // Arrange
        let file = textFile()
        let opener = FakeFileOpeningService()
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: MockFileSystemService(items: [file]),
            fileOpeningService: opener
        )
        vm.editorDefaultAppBundleID = "com.apple.TextEdit"
        await vm.reload(.fresh)
        vm.state.cursor.selected = [file.id]

        // Act
        await vm.openPreparedSelectedFileWithDefaultApp()

        // Assert
        #expect(opener.openedURLs == [file.url])
        #expect(opener.requestedBundleIDs == ["com.apple.TextEdit"])
    }

    @Test func editWithNoConfiguredEditorOpensWithSystemDefault() async {
        // Arrange
        let file = textFile()
        let opener = FakeFileOpeningService()
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: MockFileSystemService(items: [file]),
            fileOpeningService: opener
        )
        await vm.reload(.fresh)
        vm.state.cursor.selected = [file.id]

        // Act
        await vm.openPreparedSelectedFileWithDefaultApp()

        // Assert
        #expect(opener.openedURLs == [file.url])
        #expect(opener.requestedBundleIDs == [nil])
    }

    @Test func editOpensAnExtractedArchiveMemberWithTheConfiguredEditor() async {
        // Arrange
        let container = URL(fileURLWithPath: "/tmp/files.zip")
        let archiveRow = FileItem(url: container, name: "files.zip", isDirectory: false)
        let member = FileItem(
            archiveContainer: container,
            internalPath: "inside.txt",
            name: "inside.txt",
            isDirectory: false
        )
        let opener = FakeFileOpeningService()
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp"),
            fileSystemService: MockFileSystemService(items: [archiveRow]),
            archiveService: MockArchiveService(itemsByPath: ["": [member]]),
            fileOpeningService: opener
        )
        vm.editorDefaultAppBundleID = "com.apple.TextEdit"
        await vm.reload(.fresh)
        await vm.openItem(archiveRow)
        let extractedMember = vm.state.items.first { $0.name == "inside.txt" }
        vm.state.cursor.selected = [extractedMember?.id ?? UUID()]

        // Act
        await vm.openPreparedSelectedFileWithDefaultApp()

        // Assert — the temporary extraction, not the member's archive URL.
        #expect(opener.requestedBundleIDs == ["com.apple.TextEdit"])
        #expect(opener.openedURLs.count == 1)
        #expect(opener.openedURLs.first?.lastPathComponent == "inside.txt")
        #expect(opener.openedURLs.first?.path.contains("LCdrData-Preview-") == true)
    }
}
