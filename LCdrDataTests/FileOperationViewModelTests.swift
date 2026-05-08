import Testing
import Foundation
@testable import LCdrData

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

    func copy(
        sources: [URL],
        to destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws {
        copyCalled = true
        lastCopySources = sources
        lastCopyDestination = destination

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

    func trash(items: [URL]) async throws -> [URL] {
        trashCalled = true
        lastTrashItems = items

        if shouldThrowOnTrash {
            throw FileOperationError.invalidDestination
        }

        return items
    }

    func deletePermanently(items: [URL]) async throws {
        deletePermanentlyCalled = true
        lastDeletePermanentlyItems = items
        if shouldThrowOnDeletePermanently {
            throw FileOperationError.invalidDestination
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

    @Test func cancelCurrentOperationHidesProgress() {
        let mockService = MockFileOperationService()
        let vm = FileOperationViewModel(operationService: mockService)

        vm.showProgressOverlay = true
        vm.cancelCurrentOperation()

        #expect(!vm.showProgressOverlay)
    }
}
