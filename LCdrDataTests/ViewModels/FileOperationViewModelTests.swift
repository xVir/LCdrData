import Testing
import Foundation
@testable import Models
@testable import Services
@testable import ViewModels

// MARK: - Mock File Operation Service

/// A mock FileOperationService that records calls and returns controlled results.
nonisolated final class MockFileOperationService: FileOperationServiceProtocol, @unchecked Sendable {

    // Track calls
    var copyCalled = false
    var moveCalled = false
    var trashCalled = false
    var deletePermanentlyCalled = false
    var createFolderCalled = false
    var renameCalled = false

    // Arguments captured
    var lastCopySources: [URL]?
    var lastCopyDestination: URL?
    var lastMoveSources: [URL]?
    var lastMoveDestination: URL?
    var lastTrashItems: [URL]?
    var lastDeletePermanentlyItems: [URL]?
    var lastCreateFolderDirectory: URL?
    var lastCreateFolderName: String?
    var lastRenameItem: URL?
    var lastRenameNewName: String?

    // Control behavior
    var shouldThrowOnCopy = false
    var shouldThrowOnMove = false
    var shouldThrowOnTrash = false
    var shouldThrowOnDeletePermanently = false
    var shouldThrowOnCreateFolder = false
    var shouldThrowOnRename = false
    var createFolderReturnURL: URL?
    var renameReturnURL: URL?
    var createConflict = false
    var holdCopy = false
    private let copyLock = NSLock()
    private var copyContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var copyIsSuspended = false
    private(set) var copyCallCount = 0

    func resumeHeldCopy() {
        copyLock.lock()
        let continuation = copyContinuations.isEmpty ? nil : copyContinuations.removeFirst()
        copyIsSuspended = !copyContinuations.isEmpty
        copyLock.unlock()
        continuation?.resume()
    }

    func copy(
        sources: [URL],
        to destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws {
        copyCalled = true
        copyCallCount += 1
        lastCopySources = sources
        lastCopyDestination = destination

        if holdCopy {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                copyLock.lock()
                copyContinuations.append(continuation)
                copyIsSuspended = true
                copyLock.unlock()
            }
        }

        try Task.checkCancellation()

        if shouldThrowOnCopy {
            throw FileOperationError.invalidDestination
        }

        if createConflict {
            for source in sources {
                let destURL = destination.appendingPathComponent(source.lastPathComponent)
                let conflict = FileConflict.destinationExists(source: source, destination: destURL)
                let _ = await onConflict(conflict)
            }
        }

        for (index, source) in sources.enumerated() {
            onProgress(FileOperationProgress(
                totalItems: sources.count,
                completedItems: index + 1,
                currentItemName: source.lastPathComponent
            ))
        }
    }

    func move(
        sources: [URL],
        to destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws {
        moveCalled = true
        lastMoveSources = sources
        lastMoveDestination = destination

        if shouldThrowOnMove {
            throw FileOperationError.invalidDestination
        }

        for (index, source) in sources.enumerated() {
            onProgress(FileOperationProgress(
                totalItems: sources.count,
                completedItems: index + 1,
                currentItemName: source.lastPathComponent
            ))
        }
    }

    func trash(
        items: [URL],
        onProgress: @escaping @Sendable (FileOperationProgress) -> Void
    ) async throws -> [URL] {
        trashCalled = true
        lastTrashItems = items

        if shouldThrowOnTrash {
            throw FileOperationError.invalidDestination
        }

        for (index, item) in items.enumerated() {
            onProgress(FileOperationProgress(
                totalItems: items.count,
                completedItems: index + 1,
                currentItemName: item.lastPathComponent
            ))
        }
        return items
    }

    func deletePermanently(
        items: [URL],
        onProgress: @escaping @Sendable (FileOperationProgress) -> Void
    ) async throws {
        deletePermanentlyCalled = true
        lastDeletePermanentlyItems = items
        if shouldThrowOnDeletePermanently {
            throw FileOperationError.invalidDestination
        }
        for (index, item) in items.enumerated() {
            onProgress(FileOperationProgress(
                totalItems: items.count,
                completedItems: index + 1,
                currentItemName: item.lastPathComponent
            ))
        }
    }

    func createFolder(in directory: URL, name: String) async throws -> URL {
        createFolderCalled = true
        lastCreateFolderDirectory = directory
        lastCreateFolderName = name

        if shouldThrowOnCreateFolder {
            throw FileOperationError.itemAlreadyExists(name: name)
        }

        return createFolderReturnURL ?? directory.appendingPathComponent(name, isDirectory: true)
    }

    func rename(item: URL, to newName: String) async throws -> URL {
        renameCalled = true
        lastRenameItem = item
        lastRenameNewName = newName

        if shouldThrowOnRename {
            throw FileOperationError.itemAlreadyExists(name: newName)
        }

        return renameReturnURL ?? item.deletingLastPathComponent().appendingPathComponent(newName)
    }
}

// MARK: - Tests

@MainActor
struct FileOperationViewModelTests {

    private func makeMockPanelViewModel(
        directory: URL = URL(fileURLWithPath: "/tmp/source"),
        items: [FileItem] = [],
        selectedIDs: Set<UUID> = []
    ) -> PanelViewModel {
        let service = MockFileSystemService(items: items)
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: directory,
            fileSystemService: service
        )
        vm.state.items = items
        vm.state.cursor.selected = selectedIDs
        return vm
    }

    // MARK: - Selected Items

    @Test func selectedItemsExcludesParentEntry() {
        let parent = FileItem(
            url: URL(fileURLWithPath: "/tmp"),
            name: "..",
            isDirectory: true,
            isParentDirectory: true
        )
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/source/test.txt"),
            name: "test.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        let panel = makeMockPanelViewModel(
            items: [parent, file],
            selectedIDs: [parent.id, file.id]
        )

        let selected = vm.selectedItems(from: panel)
        #expect(selected.count == 1)
        #expect(selected[0].name == "test.txt")
    }

    @Test func selectedItemsReturnsEmptyWhenNothingSelected() {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/source/test.txt"),
            name: "test.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        let panel = makeMockPanelViewModel(items: [file], selectedIDs: [])

        let selected = vm.selectedItems(from: panel)
        #expect(selected.isEmpty)
    }

    // MARK: - Request Copy

    @Test func requestCopySetsConfirmationState() {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/source/test.txt"),
            name: "test.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        let sourcePanel = makeMockPanelViewModel(
            items: [file],
            selectedIDs: [file.id]
        )
        let destPanel = makeMockPanelViewModel(
            directory: URL(fileURLWithPath: "/tmp/dest")
        )

        vm.requestCopy(from: sourcePanel, to: destPanel)

        #expect(vm.showConfirmationDialog)
        #expect(vm.confirmationMessage.contains("1 item"))
        #expect(vm.pendingOperationType != nil)
    }

    @Test func requestCopyDoesNothingWithNoSelection() {
        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        let panel = makeMockPanelViewModel(items: [], selectedIDs: [])
        let destPanel = makeMockPanelViewModel()

        vm.requestCopy(from: panel, to: destPanel)

        #expect(!vm.showConfirmationDialog)
        #expect(vm.pendingOperationType == nil)
    }

    // MARK: - Request Move

    @Test func requestMoveSetsConfirmationState() {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/source/test.txt"),
            name: "test.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        let sourcePanel = makeMockPanelViewModel(
            items: [file],
            selectedIDs: [file.id]
        )
        let destPanel = makeMockPanelViewModel(
            directory: URL(fileURLWithPath: "/tmp/dest")
        )

        vm.requestMove(from: sourcePanel, to: destPanel)

        #expect(vm.showConfirmationDialog)
        #expect(vm.confirmationMessage.contains("Move"))
    }

    // MARK: - Request Delete

    @Test func requestDeleteSetsConfirmationState() {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/source/test.txt"),
            name: "test.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        let panel = makeMockPanelViewModel(
            items: [file],
            selectedIDs: [file.id]
        )

        vm.requestDelete(from: panel)

        #expect(vm.showConfirmationDialog)
        #expect(vm.confirmationMessage.contains("Trash"))
    }

    @Test func requestDeleteInsideArchiveUsesPermanentArchiveWording() {
        let container = URL(fileURLWithPath: "/tmp/files.zip")
        let file = FileItem(
            archiveContainer: container,
            internalPath: "folder/test.txt",
            name: "test.txt",
            isDirectory: false
        )
        let vm = FileOperationViewModel(operationService: MockFileOperationService())
        let panel = makeMockPanelViewModel(items: [file], selectedIDs: [file.id])
        panel.state.location = .zipArchive(container: container, internalPath: "folder")

        vm.requestDelete(from: panel)

        #expect(vm.confirmationMessage.contains("from archive"))
        #expect(!vm.confirmationMessage.contains("Trash"))
        guard case .browseDelete(let items, let source, false)? = vm.pendingOperationType else {
            Issue.record("expected archive delete operation")
            return
        }
        #expect(items == [file])
        #expect(source == panel.state.location)
    }

    @Test func requestPermanentDeleteSetsConfirmationState() {
        let file = FileItem(
            url: URL(fileURLWithPath: "/tmp/source/test.txt"),
            name: "test.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        let panel = makeMockPanelViewModel(
            items: [file],
            selectedIDs: [file.id]
        )

        vm.requestPermanentDelete(from: panel)

        #expect(vm.showConfirmationDialog)
        #expect(vm.confirmationMessage.contains("Permanently delete"))
        #expect(vm.confirmationMessage.contains("cannot be undone"))
    }

    // MARK: - Request New Folder

    @Test func requestNewFolderShowsDialog() {
        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.requestNewFolder()

        #expect(vm.showNewFolderDialog)
        #expect(vm.newFolderName == "New Folder")
    }

    @Test func performCreateFolderCallsService() async {
        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.newFolderName = "TestFolder"
        await vm.performCreateFolder(in: URL(fileURLWithPath: "/tmp"))

        #expect(mockService.createFolderCalled)
        #expect(mockService.lastCreateFolderName == "TestFolder")
        #expect(mockService.lastCreateFolderDirectory == URL(fileURLWithPath: "/tmp"))
    }

    @Test func performCreateFolderWithEmptyNameDoesNothing() async {
        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.newFolderName = "   "
        await vm.performCreateFolder(in: URL(fileURLWithPath: "/tmp"))

        #expect(!mockService.createFolderCalled)
    }

    @Test func performCreateFolderErrorShowsAlert() async {
        let mockService = MockFileOperationService()
        mockService.shouldThrowOnCreateFolder = true
        let vm = FileOperationViewModel(operationService: mockService)

        vm.newFolderName = "Existing"
        await vm.performCreateFolder(in: URL(fileURLWithPath: "/tmp"))

        #expect(vm.showErrorAlert)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Request Rename

    @Test func requestRenameShowsDialog() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/test.txt"),
            name: "test.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.requestRename(item: item)

        #expect(vm.showRenameDialog)
        #expect(vm.renameItem?.name == "test.txt")
    }

    @Test func performRenameCallsService() async {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/old.txt"),
            name: "old.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.renameItem = item
        await vm.performRename(newName: "new.txt")

        #expect(mockService.renameCalled)
        #expect(mockService.lastRenameItem == URL(fileURLWithPath: "/tmp/old.txt"))
        #expect(mockService.lastRenameNewName == "new.txt")
        #expect(vm.renameItem == nil)
    }

    @Test func performRenameWithSameNameDoesNothing() async {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/same.txt"),
            name: "same.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.renameItem = item
        await vm.performRename(newName: "same.txt")

        #expect(!mockService.renameCalled)
    }

    @Test func performRenameErrorShowsAlert() async {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/old.txt"),
            name: "old.txt",
            isDirectory: false
        )

        let mockService = MockFileOperationService()
        mockService.shouldThrowOnRename = true
        let vm = FileOperationViewModel(operationService: mockService)

        vm.renameItem = item
        await vm.performRename(newName: "conflicting.txt")

        #expect(vm.showErrorAlert)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Confirmation

    @Test func cancelConfirmationClearsPendingOperation() {
        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.pendingOperationType = .delete(items: [URL(fileURLWithPath: "/tmp/test")])
        vm.cancelConfirmation()

        #expect(vm.pendingOperationType == nil)
    }

    // MARK: - Cancel Operation

    @Test func secondCopyWaitsWhenTheWindowIsAtItsAllowance() async {
        let mock = MockFileOperationService()
        mock.holdCopy = true
        let vm = FileOperationViewModel(operationService: mock)
        vm.setAllowance(1)

        vm.pendingOperationType = browseCopy(name: "first")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { mock.copyIsSuspended }

        vm.pendingOperationType = browseCopy(name: "second")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})

        #expect(vm.running.count == 1)
        #expect(vm.waiting.count == 1)
        #expect(vm.waiting.first?.status == .pending)
        #expect(mock.copyCallCount == 1)
    }

    @Test func cancellingAWaitingCopyNeverRunsIt() async {
        let mock = MockFileOperationService()
        mock.holdCopy = true
        let vm = FileOperationViewModel(operationService: mock)
        vm.setAllowance(1)

        vm.pendingOperationType = browseCopy(name: "first")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { mock.copyIsSuspended }

        vm.pendingOperationType = browseCopy(name: "second")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        let waitingID = vm.waiting[0].id
        vm.cancel(id: waitingID)

        #expect(vm.waiting.isEmpty)
        #expect(vm.settled.first?.status == .cancelled)
        #expect(mock.copyCallCount == 1)

        mock.resumeHeldCopy()
        await waitUntil { vm.running.isEmpty }
    }

    @Test func finishingACopyStartsTheOldestWaitingCopy() async {
        let mock = MockFileOperationService()
        mock.holdCopy = true
        let vm = FileOperationViewModel(operationService: mock)
        vm.setAllowance(1)

        vm.pendingOperationType = browseCopy(name: "first")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { mock.copyIsSuspended }

        vm.pendingOperationType = browseCopy(name: "second")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})

        mock.resumeHeldCopy()
        await waitUntil { mock.copyCallCount == 2 && vm.running.count == 1 }

        #expect(vm.waiting.isEmpty)
        #expect(vm.running.count == 1)
        #expect(vm.settled.first?.status == .completed)
        mock.resumeHeldCopy()
        await waitUntil { vm.running.isEmpty }
    }

    @Test func cancelKeepsARunningCopyRunningUntilTheCurrentWriteReturns() async {
        let mock = MockFileOperationService()
        mock.holdCopy = true
        let vm = FileOperationViewModel(operationService: mock)
        vm.setAllowance(1)

        vm.pendingOperationType = browseCopy(name: "huge")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { mock.copyIsSuspended }

        vm.cancel(id: vm.running[0].id)

        #expect(vm.running.first?.status == .inProgress)
        #expect(vm.running.first?.isFinishingCurrentItem == true)

        mock.resumeHeldCopy()
        await waitUntil { vm.running.isEmpty }
        #expect(vm.settled.first?.status == .cancelled)
    }

    @Test func aFailedCopyIsASettledRowWithoutAnAlert() async {
        let mock = MockFileOperationService()
        mock.shouldThrowOnCopy = true
        let vm = FileOperationViewModel(operationService: mock)

        vm.pendingOperationType = browseCopy(name: "broken")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { !vm.settled.isEmpty }

        #expect(vm.showErrorAlert == false)
        if case .failed = vm.settled.first?.status {
        } else {
            Issue.record("expected a failed row")
        }
    }

    @Test func closingTheTaskListKeepsFinishedRowsForTheWindowSession() async {
        let mock = MockFileOperationService()
        mock.shouldThrowOnCopy = true
        let vm = FileOperationViewModel(operationService: mock)
        vm.pendingOperationType = browseCopy(name: "broken")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { !vm.settled.isEmpty }
        let finishedID = vm.settled[0].id

        mock.shouldThrowOnCopy = false
        mock.holdCopy = true
        vm.pendingOperationType = browseCopy(name: "live")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { mock.copyIsSuspended }

        vm.isTaskListPresented = true
        vm.dismissTaskList()
        vm.toggleTaskList()
        vm.toggleTaskList()

        #expect(vm.settled.contains { $0.id == finishedID })
        #expect(vm.running.count == 1)
        #expect(!vm.ringIsEmpty)
        mock.resumeHeldCopy()
        await waitUntil { vm.running.isEmpty }
        #expect(vm.settled.contains { $0.id == finishedID })
        #expect(!vm.ringIsEmpty)

        vm.toggleTaskList()
        vm.dismissTaskList()

        #expect(vm.ringIsEmpty)
        #expect(vm.settled.contains { $0.id == finishedID })
    }

    @Test func loweringTheAllowanceDoesNotCancelARunningCopy() async {
        let mock = MockFileOperationService()
        mock.holdCopy = true
        let vm = FileOperationViewModel(operationService: mock)
        vm.setAllowance(2)

        vm.pendingOperationType = browseCopy(name: "one")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { mock.copyCallCount == 1 }
        vm.pendingOperationType = browseCopy(name: "two")
        vm.confirmOperation(reloadSource: {}, reloadDestination: {})
        await waitUntil { mock.copyCallCount == 2 }

        vm.setAllowance(1)

        #expect(vm.running.count == 2)
        mock.resumeHeldCopy()
        mock.resumeHeldCopy()
        await waitUntil { vm.running.isEmpty }
    }

    private func browseCopy(name: String) -> FileOperationType {
        let item = FileItem(
            url: URL(fileURLWithPath: "/src/\(name).txt"),
            name: "\(name).txt",
            isDirectory: false
        )
        return .browseCopy(
            items: [item],
            source: .directory(URL(fileURLWithPath: "/src", isDirectory: true)),
            destination: .directory(URL(fileURLWithPath: "/dst", isDirectory: true))
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        limit: Int = 50
    ) async {
        for _ in 0..<limit {
            if condition() { return }
            await Task.yield()
        }
    }
}
