import Foundation

/// Describes the type of conflict encountered during a file operation.
enum FileConflict: Sendable {
    case destinationExists(source: URL, destination: URL)
}

/// Describes how to resolve a file conflict.
enum ConflictResolution: Sendable {
    case overwrite
    case skip
    case rename(newName: String)
}

/// Describes a file operation to perform.
enum FileOperationType: Sendable, Equatable {
    case copy(sources: [URL], destination: URL)
    case move(sources: [URL], destination: URL)
    case delete(items: [URL])
    case createFolder(at: URL, name: String)
    case rename(item: URL, newName: String)
}

/// Reports progress for a file operation.
struct FileOperationProgress: Sendable {
    let totalItems: Int
    let completedItems: Int
    let currentItemName: String

    var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }
}

/// Protocol defining file operation capabilities for testability.
nonisolated protocol FileOperationServiceProtocol: Sendable {
    /// Copies files from source URLs to a destination directory.
    /// Calls `onProgress` for each item completed.
    /// Calls `onConflict` when a destination file already exists, returning the resolution.
    func copy(
        sources: [URL],
        to destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws

    /// Moves files from source URLs to a destination directory.
    func move(
        sources: [URL],
        to destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws

    /// Moves files to Trash.
    func trash(items: [URL]) async throws -> [URL]

    /// Creates a new folder at the specified URL with the given name.
    func createFolder(in directory: URL, name: String) async throws -> URL

    /// Renames an item at the specified URL to a new name.
    func rename(item: URL, to newName: String) async throws -> URL
}

/// Concrete implementation using Foundation's FileManager.
nonisolated final class FileOperationService: FileOperationServiceProtocol, Sendable {

    func copy(
        sources: [URL],
        to destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws {
        try await performBatchOperation(
            sources: sources,
            destination: destination,
            onProgress: onProgress,
            onConflict: onConflict,
            perform: { fm, source, dest in
                try fm.copyItem(at: source, to: dest)
            }
        )
    }

    func move(
        sources: [URL],
        to destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws {
        try await performBatchOperation(
            sources: sources,
            destination: destination,
            onProgress: onProgress,
            onConflict: onConflict,
            perform: { fm, source, dest in
                try fm.moveItem(at: source, to: dest)
            }
        )
    }

    func trash(items: [URL]) async throws -> [URL] {
        return try await Task.detached {
            let fm = FileManager()
            var trashedURLs: [URL] = []

            for item in items {
                var resultingURL: NSURL?
                try fm.trashItem(at: item, resultingItemURL: &resultingURL)
                if let trashedURL = resultingURL as URL? {
                    trashedURLs.append(trashedURL)
                }
            }

            return trashedURLs
        }.value
    }

    func createFolder(in directory: URL, name: String) async throws -> URL {
        return try await Task.detached {
            let fm = FileManager()
            let folderURL = directory.appendingPathComponent(name, isDirectory: true)

            guard !fm.fileExists(atPath: folderURL.path) else {
                throw FileOperationError.itemAlreadyExists(name: name)
            }

            try fm.createDirectory(at: folderURL, withIntermediateDirectories: false)
            return folderURL
        }.value
    }

    func rename(item: URL, to newName: String) async throws -> URL {
        return try await Task.detached {
            let fm = FileManager()
            let newURL = item.deletingLastPathComponent()
                .appendingPathComponent(newName)

            guard !fm.fileExists(atPath: newURL.path) else {
                throw FileOperationError.itemAlreadyExists(name: newName)
            }

            try fm.moveItem(at: item, to: newURL)
            return newURL
        }.value
    }

    // MARK: - Private Helpers

    /// Performs a batch file operation (copy or move) with progress and conflict handling.
    private func performBatchOperation(
        sources: [URL],
        destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution,
        perform: @Sendable (FileManager, URL, URL) throws -> Void
    ) async throws {
        let totalItems = sources.count

        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()

            let itemName = source.lastPathComponent
            var destinationURL = destination.appendingPathComponent(itemName)

            // Check for conflicts
            let fm = FileManager()
            if fm.fileExists(atPath: destinationURL.path) {
                let conflict = FileConflict.destinationExists(
                    source: source,
                    destination: destinationURL
                )
                let resolution = await onConflict(conflict)

                switch resolution {
                case .overwrite:
                    try fm.removeItem(at: destinationURL)
                case .skip:
                    onProgress(FileOperationProgress(
                        totalItems: totalItems,
                        completedItems: index + 1,
                        currentItemName: itemName
                    ))
                    continue
                case .rename(let newName):
                    destinationURL = destination.appendingPathComponent(newName)
                }
            }

            try perform(fm, source, destinationURL)

            onProgress(FileOperationProgress(
                totalItems: totalItems,
                completedItems: index + 1,
                currentItemName: itemName
            ))
        }
    }
}

/// Errors specific to file operations.
enum FileOperationError: LocalizedError, Equatable {
    case itemAlreadyExists(name: String)
    case operationCancelled
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .itemAlreadyExists(let name):
            return "An item named \"\(name)\" already exists."
        case .operationCancelled:
            return "The operation was cancelled."
        case .invalidDestination:
            return "The destination is not valid."
        }
    }
}
