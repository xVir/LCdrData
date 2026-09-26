import Foundation
import Observation
import Models
import Services

/// Manages file operations, progress tracking, confirmation dialogs,
/// and conflict resolution for the dual-panel file manager.
@Observable
package final class FileOperationViewModel {

    // MARK: - State

    /// Tasks that have started. Oldest first. Each holds one allowance slot.
    package var running: [FileOperation] = []

    /// Confirmed tasks that have not started, because the window is at its allowance. Oldest first.
    package var waiting: [FileOperation] = []

    /// Finished, failed, and cancelled tasks, oldest first.
    package var settled: [FileOperation] = []

    /// How many tasks may run at once in this window. Values below 1 are ignored.
    package private(set) var maxActive: Int = 3

    private let listPolicy = TaskListPolicy()

    /// The task list: every running task, every waiting task, then history.
    package var visibleOperations: [FileOperation] {
        listPolicy.visible(running: running, waiting: waiting, settledNewestLast: settled)
    }

    package var indicatorState: TaskIndicatorState {
        listPolicy.indicatorState(running: running, waiting: waiting, settled: settled)
    }

    package var hasUnfinishedBackgroundTasks: Bool {
        !running.isEmpty || !waiting.isEmpty
    }

    /// Whether a confirmation dialog should be shown.
    package var showConfirmationDialog: Bool = false

    /// Description for the confirmation dialog.
    package var confirmationMessage: String = ""

    /// The pending operation awaiting confirmation.
    package var pendingOperationType: FileOperationType?

    /// Whether the conflict resolution dialog should be shown.
    package var showConflictDialog: Bool = false

    /// The current conflict awaiting resolution.
    package var currentConflict: FileConflict?

    /// The stored resolution when "apply to all" is active, per operation.
    private var storedResolutionByOperation: [UUID: ConflictResolution] = [:]

    /// Operations whose conflicts are answered by `storedResolutionByOperation`.
    private var applyToAllOperations: Set<UUID> = []

    /// Running tasks, keyed by operation id. Waiting tasks are not here.
    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Work that has been confirmed and is either running or waiting.
    private var queuedWork: [UUID: QueuedWork] = [:]

    /// Conflict questions waiting for the one sheet, in the order they were raised.
    private var conflictQueue: [ConflictRequest] = []

    /// The conflict currently on the sheet.
    private var presentedConflict: ConflictRequest?

    /// Error message to display if an operation fails.
    package var errorMessage: String?

    /// Whether to show the error alert.
    package var showErrorAlert: Bool = false

    /// Whether the new folder dialog should be shown.
    package var showNewFolderDialog: Bool = false

    /// The name entered for the new folder.
    package var newFolderName: String = ""

    /// Whether the rename dialog should be shown.
    package var showRenameDialog: Bool = false

    /// The item being renamed.
    package var renameItem: FileItem?

    // MARK: - Dependencies

    private let operationService: FileOperationServiceProtocol
    private let browseOperationService: BrowseOperationServiceProtocol

    // MARK: - Init

    package init(
        operationService: FileOperationServiceProtocol = FileOperationService(),
        browseOperationService: BrowseOperationServiceProtocol? = nil
    ) {
        self.operationService = operationService
        self.browseOperationService = browseOperationService
            ?? BrowseOperationService(fileService: operationService)
    }

    // MARK: - Selected Items Helper

    /// Returns the selected non-parent items from the active panel.
    package func selectedItems(from panel: PanelViewModel) -> [FileItem] {
        panel.state.items.filter { item in
            panel.state.cursor.selected.contains(item.id) && !item.isParentDirectory
        }
    }

    // MARK: - Copy

    /// Initiates a copy operation from selected items in the source panel to the destination.
    package func requestCopy(
        from sourcePanel: PanelViewModel,
        to destinationPanel: PanelViewModel
    ) {
        let items = selectedItems(from: sourcePanel)
        guard !items.isEmpty else { return }

        let destination = destinationPanel.state.location

        let count = items.count
        let itemWord = count == 1 ? "item" : "items"
        confirmationMessage = "Copy \(count) \(itemWord) to \(destination.displayPath)?"
        pendingOperationType = .browseCopy(
            items: items,
            source: sourcePanel.state.location,
            destination: destination
        )
        showConfirmationDialog = true
    }

    // MARK: - Move

    /// Initiates a move operation from selected items in the source panel to the destination.
    package func requestMove(
        from sourcePanel: PanelViewModel,
        to destinationPanel: PanelViewModel
    ) {
        let items = selectedItems(from: sourcePanel)
        guard !items.isEmpty else { return }

        let destination = destinationPanel.state.location

        let count = items.count
        let itemWord = count == 1 ? "item" : "items"
        confirmationMessage = "Move \(count) \(itemWord) to \(destination.displayPath)?"
        pendingOperationType = .browseMove(
            items: items,
            source: sourcePanel.state.location,
            destination: destination
        )
        showConfirmationDialog = true
    }

    /// Copies file URLs supplied by an external drag into a panel location.
    package func performDrop(
        urls: [URL],
        to destination: BrowseLocation,
        reloadDestination: @escaping () async -> Void = {}
    ) async {
        let items = urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory == true
            )
        }
        guard !items.isEmpty else { return }

        let source = BrowseLocation.directory(urls[0].deletingLastPathComponent())
        enqueue(
            .browseCopy(items: items, source: source, destination: destination),
            reloadSource: {},
            reloadDestination: reloadDestination
        )
    }

    // MARK: - Delete

    /// Initiates a delete (trash) operation for selected items in the panel.
    package func requestDelete(from panel: PanelViewModel) {
        let items = selectedItems(from: panel)
        guard !items.isEmpty else { return }

        let count = items.count
        let itemWord = count == 1 ? "item" : "items"
        switch panel.state.location {
        case .directory:
            confirmationMessage = "Move \(count) \(itemWord) to Trash?"
        case .zipArchive:
            confirmationMessage = "Delete \(count) \(itemWord) from archive? This cannot be undone."
        }
        pendingOperationType = .browseDelete(
            items: items,
            source: panel.state.location,
            permanently: false
        )
        showConfirmationDialog = true
    }

    /// Initiates immediate removal from disk (not Trash). Requires confirmation.
    package func requestPermanentDelete(from panel: PanelViewModel) {
        let items = selectedItems(from: panel)
        guard !items.isEmpty else { return }

        let count = items.count
        let itemWord = count == 1 ? "item" : "items"
        confirmationMessage =
            "Permanently delete \(count) \(itemWord)? This cannot be undone."
        pendingOperationType = .browseDelete(
            items: items,
            source: panel.state.location,
            permanently: true
        )
        showConfirmationDialog = true
    }

    // MARK: - New Folder

    /// Shows the new folder dialog.
    package func requestNewFolder() {
        newFolderName = "New Folder"
        showNewFolderDialog = true
    }

    /// Creates a new folder in the specified directory.
    package func performCreateFolder(in directory: URL) async {
        await performCreateFolder(at: .directory(directory))
    }

    /// Creates a new folder at a filesystem or archive location.
    package func performCreateFolder(at location: BrowseLocation) async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            try await browseOperationService.createDirectory(at: location, name: name)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    // MARK: - Rename

    /// Shows the rename dialog for the given item.
    package func requestRename(item: FileItem) {
        renameItem = item
        showRenameDialog = true
    }

    /// Performs the rename of the item.
    package func performRename(newName: String) async {
        guard let item = renameItem else { return }
        guard !newName.isEmpty, newName != item.name else {
            renameItem = nil
            return
        }

        do {
            let location: BrowseLocation
            if let container = item.archiveContainer, let internalPath = item.archiveInternalPath {
                let parentPath = (internalPath as NSString).deletingLastPathComponent
                location = .zipArchive(
                    container: container,
                    internalPath: parentPath == "." ? "" : parentPath
                )
            } else {
                location = .directory(item.url.deletingLastPathComponent())
            }
            try await browseOperationService.rename(item: item, at: location, to: newName)
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        renameItem = nil
    }


    // MARK: - Confirmation Handling

    /// Called when the user confirms a pending operation.
    package func confirmOperation(
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) {
        guard let operation = pendingOperationType else { return }
        pendingOperationType = nil

        switch operation {
        case .createFolder(let directory, let name):
            newFolderName = name
            Task {
                await performCreateFolder(in: directory)
                await reloadSource()
                await reloadDestination()
            }
        case .rename(let item, let newName):
            renameItem = FileItem(url: item, name: item.lastPathComponent, isDirectory: false)
            Task {
                await performRename(newName: newName)
                await reloadSource()
                await reloadDestination()
            }
        default:
            enqueue(operation, reloadSource: reloadSource, reloadDestination: reloadDestination)
        }
    }

    /// Called when the user cancels a pending operation.
    package func cancelConfirmation() {
        pendingOperationType = nil
    }

    /// Lowers or raises how many tasks may run. Running tasks are left alone.
    /// A value below 1 is ignored.
    package func setAllowance(_ value: Int) {
        guard value >= 1 else { return }
        maxActive = value
        startWaitingIfSlotsFree()
    }

    /// Stops one task. A waiting task never starts. A running task stays running
    /// until the current item's write returns.
    package func cancel(id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) {
            var operation = waiting.remove(at: index)
            operation.status = .cancelled
            queuedWork[id] = nil
            appendSettled(operation)
            return
        }
        guard let index = running.firstIndex(where: { $0.id == id }) else { return }
        running[index].isFinishingCurrentItem = true
        cancelConflictWait(id)
        tasks[id]?.cancel()
    }

    package func cancelAllUnfinished() {
        for id in waiting.map(\.id) {
            cancel(id: id)
        }
        for id in running.map(\.id) {
            cancel(id: id)
        }
    }

    /// Whether the task list is open. The ring lives in the title bar, and the
    /// list is drawn in the window under it.
    package var isTaskListPresented = false

    /// After the list is closed with nothing still running, the ring is drawn empty
    /// until the next operation starts. Finished rows stay in the list.
    package private(set) var ringIsEmpty = false

    private var lastTaskListToggle: TimeInterval = 0

    package func toggleTaskList() {
        let now = ProcessInfo.processInfo.systemUptime
        // A title-bar click can be delivered twice: once to the ring, once to the button.
        if now - lastTaskListToggle < 0.05 { return }
        lastTaskListToggle = now
        isTaskListPresented.toggle()
        if !isTaskListPresented {
            emptyRingIfIdle()
        }
    }

    package func dismissTaskList() {
        guard isTaskListPresented else { return }
        isTaskListPresented = false
        emptyRingIfIdle()
    }

    private func emptyRingIfIdle() {
        if running.isEmpty && waiting.isEmpty {
            ringIsEmpty = true
        }
    }

    // MARK: - Queue

    private struct QueuedWork {
        var operation: FileOperation
        let type: FileOperationType
        let reloadSource: () async -> Void
        let reloadDestination: () async -> Void
    }

    private struct ConflictRequest {
        let operationID: UUID
        let conflict: FileConflict
        let continuation: CheckedContinuation<ConflictResolution, Never>
    }

    private func enqueue(
        _ type: FileOperationType,
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) {
        let id = UUID()
        let operation = trackedOperation(id: id, type: type, status: .pending)
        queuedWork[id] = QueuedWork(
            operation: operation,
            type: type,
            reloadSource: reloadSource,
            reloadDestination: reloadDestination
        )
        if running.count < maxActive {
            promote(id)
        } else {
            waiting.append(operation)
        }
    }

    private func promote(_ id: UUID) {
        guard var work = queuedWork[id] else { return }
        waiting.removeAll { $0.id == id }
        work.operation.status = .inProgress
        queuedWork[id] = work
        ringIsEmpty = false
        running.append(work.operation)
        tasks[id] = Task { [weak self] in
            await self?.run(id)
        }
    }

    private func startWaitingIfSlotsFree() {
        while running.count < maxActive, let next = waiting.first {
            promote(next.id)
        }
    }

    private func run(_ id: UUID) async {
        guard let work = queuedWork[id] else { return }
        let status: FileOperationStatus
        do {
            try await perform(work.type, operationID: id)
            try Task.checkCancellation()
            status = .completed
        } catch is CancellationError {
            status = .cancelled
        } catch {
            status = .failed(error.localizedDescription)
        }
        await finish(id, status: status, work: work)
    }

    private func finish(_ id: UUID, status: FileOperationStatus, work: QueuedWork) async {
        tasks[id] = nil
        queuedWork[id] = nil
        storedResolutionByOperation[id] = nil
        applyToAllOperations.remove(id)
        if let index = running.firstIndex(where: { $0.id == id }) {
            var operation = running.remove(at: index)
            operation.status = status
            operation.isFinishingCurrentItem = false
            appendSettled(operation)
        }
        await work.reloadSource()
        await work.reloadDestination()
        startWaitingIfSlotsFree()
    }

    private func perform(_ type: FileOperationType, operationID: UUID) async throws {
        let onProgress: @Sendable (FileOperationProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.updateProgress(operationID: operationID, progress: progress)
            }
        }
        let onConflict: @Sendable (FileConflict) async -> ConflictResolution = { [weak self] conflict in
            guard let self else { return .skip }
            return await self.resolveConflict(conflict, operationID: operationID)
        }

        switch type {
        case .copy(let sources, let destination):
            try await operationService.copy(
                sources: sources,
                to: destination,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case .move(let sources, let destination):
            try await operationService.move(
                sources: sources,
                to: destination,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case .delete(let items):
            _ = try await operationService.trash(items: items, onProgress: onProgress)
        case .permanentDelete(let items):
            try await operationService.deletePermanently(items: items, onProgress: onProgress)
        case .browseCopy(let items, let source, let destination):
            try await browseOperationService.copy(
                items: items,
                from: source,
                to: destination,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case .browseMove(let items, let source, let destination):
            try await browseOperationService.move(
                items: items,
                from: source,
                to: destination,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case .browseDelete(let items, let source, let permanently):
            try await browseOperationService.delete(
                items: items,
                from: source,
                permanently: permanently,
                onProgress: onProgress
            )
        case .createFolder, .rename:
            break
        }
    }

    private func trackedOperation(
        id: UUID,
        type: FileOperationType,
        status: FileOperationStatus
    ) -> FileOperation {
        switch type {
        case .copy(let sources, let destination):
            return FileOperation(
                id: id,
                kind: .copy,
                sourceURLs: sources,
                destinationURL: destination,
                status: status
            )
        case .move(let sources, let destination):
            return FileOperation(
                id: id,
                kind: .move,
                sourceURLs: sources,
                destinationURL: destination,
                status: status
            )
        case .delete(let items):
            return FileOperation(id: id, kind: .delete, sourceURLs: items, status: status)
        case .permanentDelete(let items):
            return FileOperation(id: id, kind: .permanentDelete, sourceURLs: items, status: status)
        case .browseCopy(let items, _, let destination):
            return FileOperation(
                id: id,
                kind: .copy,
                sourceURLs: items.map(\.url),
                destinationURL: destination.watchURL,
                status: status
            )
        case .browseMove(let items, _, let destination):
            return FileOperation(
                id: id,
                kind: .move,
                sourceURLs: items.map(\.url),
                destinationURL: destination.watchURL,
                status: status
            )
        case .browseDelete(let items, _, let permanently):
            return FileOperation(
                id: id,
                kind: permanently ? .permanentDelete : .delete,
                sourceURLs: items.map(\.url),
                status: status
            )
        case .createFolder, .rename:
            return FileOperation(id: id, kind: .rename, sourceURLs: [], status: status)
        }
    }

    private func appendSettled(_ operation: FileOperation) {
        settled.append(operation)
        let overflow = settled.count - TaskListPolicy.settledCapacity
        if overflow > 0 {
            settled.removeFirst(overflow)
        }
    }

    private func updateProgress(operationID: UUID, progress: FileOperationProgress) {
        guard let index = running.firstIndex(where: { $0.id == operationID }) else { return }
        running[index].progress = progress
    }

    // MARK: - Conflict Resolution

    /// Resolves a file conflict for one running task. "Apply to all" does not
    /// answer any other task. A second task waits until the sheet is free.
    private func resolveConflict(
        _ conflict: FileConflict,
        operationID: UUID
    ) async -> ConflictResolution {
        if applyToAllOperations.contains(operationID),
           let stored = storedResolutionByOperation[operationID] {
            return stored
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                conflictQueue.append(
                    ConflictRequest(
                        operationID: operationID,
                        conflict: conflict,
                        continuation: continuation
                    )
                )
                presentNextConflict()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelConflictWait(operationID)
            }
        }
    }

    private func presentNextConflict() {
        guard presentedConflict == nil, !conflictQueue.isEmpty else { return }
        let request = conflictQueue.removeFirst()
        presentedConflict = request
        currentConflict = request.conflict
        showConflictDialog = true
    }

    /// Called when the user selects a conflict resolution.
    package func resolveCurrentConflict(with resolution: ConflictResolution, applyToAll: Bool) {
        guard let request = presentedConflict else { return }
        if applyToAll {
            applyToAllOperations.insert(request.operationID)
            storedResolutionByOperation[request.operationID] = resolution
        }
        presentedConflict = nil
        showConflictDialog = false
        currentConflict = nil
        request.continuation.resume(returning: resolution)
        presentNextConflict()
    }

    /// Resumes a task that is blocked on the conflict sheet so cancellation can proceed.
    private func cancelConflictWait(_ operationID: UUID) {
        if let presented = presentedConflict, presented.operationID == operationID {
            presentedConflict = nil
            showConflictDialog = false
            currentConflict = nil
            presented.continuation.resume(returning: .skip)
            presentNextConflict()
        }
        var kept: [ConflictRequest] = []
        for request in conflictQueue {
            if request.operationID == operationID {
                request.continuation.resume(returning: .skip)
            } else {
                kept.append(request)
            }
        }
        conflictQueue = kept
    }
}
