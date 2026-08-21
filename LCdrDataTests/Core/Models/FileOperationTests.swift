import Testing
import Foundation
@testable import Core

struct FileOperationTests {

    // MARK: - FileOperation Model

    @Test func displayDescriptionForCopy() {
        let op = FileOperation(
            kind: .copy,
            sourceURLs: [
                URL(fileURLWithPath: "/a"),
                URL(fileURLWithPath: "/b"),
            ]
        )
        #expect(op.displayDescription == "Copying 2 items")
    }

    @Test func displayDescriptionForSingleCopy() {
        let op = FileOperation(
            kind: .copy,
            sourceURLs: [URL(fileURLWithPath: "/a")]
        )
        #expect(op.displayDescription == "Copying 1 item")
    }

    @Test func displayDescriptionForMove() {
        let op = FileOperation(
            kind: .move,
            sourceURLs: [URL(fileURLWithPath: "/a")]
        )
        #expect(op.displayDescription == "Moving 1 item")
    }

    @Test func displayDescriptionForDelete() {
        let op = FileOperation(
            kind: .delete,
            sourceURLs: [
                URL(fileURLWithPath: "/a"),
                URL(fileURLWithPath: "/b"),
                URL(fileURLWithPath: "/c"),
            ]
        )
        #expect(op.displayDescription == "Deleting 3 items")
    }

    @Test func displayDescriptionForPermanentDelete() {
        let op = FileOperation(
            kind: .permanentDelete,
            sourceURLs: [URL(fileURLWithPath: "/a")]
        )
        #expect(op.displayDescription == "Permanently deleting 1 item")
    }

    @Test func displayDescriptionForCreateFolder() {
        let op = FileOperation(
            kind: .createFolder,
            sourceURLs: []
        )
        #expect(op.displayDescription == "Creating folder")
    }

    @Test func displayDescriptionForRename() {
        let op = FileOperation(
            kind: .rename,
            sourceURLs: [URL(fileURLWithPath: "/a")]
        )
        #expect(op.displayDescription == "Renaming")
    }

    @Test func defaultStatusIsPending() {
        let op = FileOperation(
            kind: .copy,
            sourceURLs: [URL(fileURLWithPath: "/a")]
        )
        #expect(op.status == .pending)
    }

    // MARK: - FileOperationProgress

    @Test func fractionCompletedCalculation() {
        let progress = FileOperationProgress(
            totalItems: 10,
            completedItems: 5,
            currentItemName: "test.txt"
        )
        #expect(progress.fractionCompleted == 0.5)
    }

    @Test func fractionCompletedZeroTotal() {
        let progress = FileOperationProgress(
            totalItems: 0,
            completedItems: 0,
            currentItemName: ""
        )
        #expect(progress.fractionCompleted == 0.0)
    }

    @Test func fractionCompletedFullyDone() {
        let progress = FileOperationProgress(
            totalItems: 3,
            completedItems: 3,
            currentItemName: "last.txt"
        )
        #expect(progress.fractionCompleted == 1.0)
    }

    // MARK: - FileOperationKind

    @Test func operationKindEquality() {
        #expect(FileOperationKind.copy == FileOperationKind.copy)
        #expect(FileOperationKind.copy != FileOperationKind.move)
        #expect(FileOperationKind.delete == FileOperationKind.delete)
        #expect(FileOperationKind.permanentDelete == FileOperationKind.permanentDelete)
        #expect(FileOperationKind.delete != FileOperationKind.permanentDelete)
        #expect(FileOperationKind.createFolder == FileOperationKind.createFolder)
        #expect(FileOperationKind.rename == FileOperationKind.rename)
    }

    // MARK: - FileOperationStatus

    @Test func statusEquality() {
        #expect(FileOperationStatus.pending == FileOperationStatus.pending)
        #expect(FileOperationStatus.inProgress == FileOperationStatus.inProgress)
        #expect(FileOperationStatus.completed == FileOperationStatus.completed)
        #expect(FileOperationStatus.cancelled == FileOperationStatus.cancelled)
        #expect(FileOperationStatus.failed("err") == FileOperationStatus.failed("err"))
        #expect(FileOperationStatus.failed("a") != FileOperationStatus.failed("b"))
        #expect(FileOperationStatus.pending != FileOperationStatus.completed)
    }
}
