import Foundation
import Observation
import Models
import Services

/// Manages file operations, progress tracking, confirmation dialogs,
/// and conflict resolution for the dual-panel file manager.
@Observable
package final class FileOperationViewModel {

    // MARK: - State

    /// Currently active operations.
    package var activeOperations: [FileOperation] = []

    /// Whether the progress overlay should be shown.
    package var showProgressOverlay: Bool = false

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

    /// Whether to apply the chosen resolution to all remaining conflicts.
    package var applyToAll: Bool = false

    /// The stored resolution when "apply to all" is active.
    private var storedResolution: ConflictResolution?

    /// The continuation used to resume after the user resolves a conflict.
    private var conflictContinuation: CheckedContinuation<ConflictResolution, Never>?

    /// The continuation used to resume after the user confirms an operation.
    private var confirmationContinuation: CheckedContinuation<Bool, Never>?

    /// The current operation task, used for cancellation.
    private var currentTask: Task<Void, Never>?

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
    package func performDrop(urls: [URL], to destination: BrowseLocation) async {
        let items = urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory == true
            )
        }
        guard !items.isEmpty else { return }

        do {
            try await browseOperationService.copy(
                items: items,
                from: .directory(urls[0].deletingLastPathComponent()),
                to: destination,
                onProgress: { _ in },
                onConflict: { [weak self] conflict in
                    guard let self else { return .skip }
                    return await self.resolveConflict(conflict)
                }
            )
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
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

        currentTask = Task {
            await executeOperation(
                operation,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )
        }
    }

    /// Called when the user cancels a pending operation.
    package func cancelConfirmation() {
        pendingOperationType = nil
    }

    // MARK: - Operation Execution

    /// Executes a confirmed file operation.
    private func executeOperation(
        _ operation: FileOperationType,
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) async {
        // Reset conflict state for this operation
        applyToAll = false
        storedResolution = nil

        switch operation {
        case .copy(let sources, let destination):
            await executeCopy(
                sources: sources,
                destination: destination,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )

        case .move(let sources, let destination):
            await executeMove(
                sources: sources,
                destination: destination,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )

        case .delete(let items):
            await executeDelete(
                items: items,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )

        case .permanentDelete(let items):
            await executePermanentDelete(
                items: items,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )

        case .createFolder(let directory, let name):
            newFolderName = name
            await performCreateFolder(in: directory)
            await reloadSource()
            await reloadDestination()

        case .rename(let item, let newName):
            renameItem = FileItem(url: item, name: item.lastPathComponent, isDirectory: false)
            await performRename(newName: newName)
            await reloadSource()
            await reloadDestination()

        case .browseCopy(let items, let source, let destination):
            await executeBrowseTransfer(
                kind: .copy,
                items: items,
                source: source,
                destination: destination,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )

        case .browseMove(let items, let source, let destination):
            await executeBrowseTransfer(
                kind: .move,
                items: items,
                source: source,
                destination: destination,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )

        case .browseDelete(let items, let source, let permanently):
            await executeBrowseDelete(
                items: items,
                source: source,
                permanently: permanently,
                reloadSource: reloadSource,
                reloadDestination: reloadDestination
            )
        }
    }

    private func executeBrowseTransfer(
        kind: FileOperationKind,
        items: [FileItem],
        source: BrowseLocation,
        destination: BrowseLocation,
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) async {
        let operationID = UUID()
        activeOperations.append(
            FileOperation(
                id: operationID,
                kind: kind,
                sourceURLs: items.map(\.url),
                destinationURL: destination.watchURL,
                status: .inProgress
            )
        )
        showProgressOverlay = true

        do {
            let onProgress: @Sendable (FileOperationProgress) -> Void = { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateProgress(operationID: operationID, progress: progress)
                }
            }
            let onConflict: @Sendable (FileConflict) async -> ConflictResolution = { [weak self] conflict in
                guard let self else { return .skip }
                return await self.resolveConflict(conflict)
            }
            if kind == .copy {
                try await browseOperationService.copy(
                    items: items,
                    from: source,
                    to: destination,
                    onProgress: onProgress,
                    onConflict: onConflict
                )
            } else {
                try await browseOperationService.move(
                    items: items,
                    from: source,
                    to: destination,
                    onProgress: onProgress,
                    onConflict: onConflict
                )
            }
            updateStatus(operationID: operationID, status: .completed)
        } catch is CancellationError {
            updateStatus(operationID: operationID, status: .cancelled)
        } catch {
            updateStatus(operationID: operationID, status: .failed(error.localizedDescription))
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        showProgressOverlay = false
        await reloadSource()
        await reloadDestination()
        cleanUpCompletedOperations(operationID: operationID)
    }

    private func executeBrowseDelete(
        items: [FileItem],
        source: BrowseLocation,
        permanently: Bool,
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) async {
        do {
            try await browseOperationService.delete(
                items: items,
                from: source,
                permanently: permanently
            )
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
        await reloadSource()
        await reloadDestination()
    }

    private func executeCopy(
        sources: [URL],
        destination: URL,
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) async {
        let operationID = UUID()
        let operation = FileOperation(
            id: operationID,
            kind: .copy,
            sourceURLs: sources,
            destinationURL: destination,
            status: .inProgress
        )
        activeOperations.append(operation)
        showProgressOverlay = true

        do {
            try await operationService.copy(
                sources: sources,
                to: destination,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateProgress(operationID: operationID, progress: progress)
                    }
                },
                onConflict: { [weak self] conflict in
                    guard let self else { return .skip }
                    return await self.resolveConflict(conflict)
                }
            )
            updateStatus(operationID: operationID, status: .completed)
        } catch is CancellationError {
            updateStatus(operationID: operationID, status: .cancelled)
        } catch {
            updateStatus(operationID: operationID, status: .failed(error.localizedDescription))
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        showProgressOverlay = false
        await reloadSource()
        await reloadDestination()

        // Clean up completed operations after a short delay
        cleanUpCompletedOperations(operationID: operationID)
    }

    private func executeMove(
        sources: [URL],
        destination: URL,
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) async {
        let operationID = UUID()
        let operation = FileOperation(
            id: operationID,
            kind: .move,
            sourceURLs: sources,
            destinationURL: destination,
            status: .inProgress
        )
        activeOperations.append(operation)
        showProgressOverlay = true

        do {
            try await operationService.move(
                sources: sources,
                to: destination,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateProgress(operationID: operationID, progress: progress)
                    }
                },
                onConflict: { [weak self] conflict in
                    guard let self else { return .skip }
                    return await self.resolveConflict(conflict)
                }
            )
            updateStatus(operationID: operationID, status: .completed)
        } catch is CancellationError {
            updateStatus(operationID: operationID, status: .cancelled)
        } catch {
            updateStatus(operationID: operationID, status: .failed(error.localizedDescription))
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        showProgressOverlay = false
        await reloadSource()
        await reloadDestination()

        cleanUpCompletedOperations(operationID: operationID)
    }

    private func executeDelete(
        items: [URL],
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) async {
        let operationID = UUID()
        let operation = FileOperation(
            id: operationID,
            kind: .delete,
            sourceURLs: items,
            status: .inProgress
        )
        activeOperations.append(operation)

        do {
            _ = try await operationService.trash(items: items)
            updateStatus(operationID: operationID, status: .completed)
        } catch {
            updateStatus(operationID: operationID, status: .failed(error.localizedDescription))
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        await reloadSource()
        await reloadDestination()

        cleanUpCompletedOperations(operationID: operationID)
    }

    private func executePermanentDelete(
        items: [URL],
        reloadSource: @escaping () async -> Void,
        reloadDestination: @escaping () async -> Void
    ) async {
        let operationID = UUID()
        let operation = FileOperation(
            id: operationID,
            kind: .permanentDelete,
            sourceURLs: items,
            status: .inProgress
        )
        activeOperations.append(operation)

        do {
            try await operationService.deletePermanently(items: items)
            updateStatus(operationID: operationID, status: .completed)
        } catch {
            updateStatus(operationID: operationID, status: .failed(error.localizedDescription))
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        await reloadSource()
        await reloadDestination()

        cleanUpCompletedOperations(operationID: operationID)
    }

    // MARK: - Conflict Resolution

    /// Resolves a file conflict, either from stored resolution or by prompting the user.
    private func resolveConflict(_ conflict: FileConflict) async -> ConflictResolution {
        if applyToAll, let stored = storedResolution {
            return stored
        }

        return await withCheckedContinuation { continuation in
            self.conflictContinuation = continuation
            self.currentConflict = conflict
            self.showConflictDialog = true
        }
    }

    /// Called when the user selects a conflict resolution.
    package func resolveCurrentConflict(with resolution: ConflictResolution, applyToAll: Bool) {
        self.applyToAll = applyToAll
        if applyToAll {
            self.storedResolution = resolution
        }

        showConflictDialog = false
        currentConflict = nil
        conflictContinuation?.resume(returning: resolution)
        conflictContinuation = nil
    }

    // MARK: - Cancellation

    /// Cancels the current running operation.
    package func cancelCurrentOperation() {
        currentTask?.cancel()
        currentTask = nil
        showProgressOverlay = false
    }

    // MARK: - Progress Tracking

    private func updateProgress(operationID: UUID, progress: FileOperationProgress) {
        guard let index = activeOperations.firstIndex(where: { $0.id == operationID }) else {
            return
        }
        activeOperations[index].progress = progress
    }

    private func updateStatus(operationID: UUID, status: FileOperationStatus) {
        guard let index = activeOperations.firstIndex(where: { $0.id == operationID }) else {
            return
        }
        activeOperations[index].status = status
    }

    private func cleanUpCompletedOperations(operationID: UUID) {
        activeOperations.removeAll { $0.id == operationID }
    }
}
