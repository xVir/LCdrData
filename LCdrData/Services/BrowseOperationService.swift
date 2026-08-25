import Foundation
import Models

package nonisolated protocol BrowseOperationServiceProtocol: Sendable {
    func copy(
        items: [FileItem],
        from source: BrowseLocation,
        to destination: BrowseLocation,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws

    func move(
        items: [FileItem],
        from source: BrowseLocation,
        to destination: BrowseLocation,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws

    func delete(items: [FileItem], from source: BrowseLocation, permanently: Bool) async throws
    func createDirectory(at location: BrowseLocation, name: String) async throws
    func rename(item: FileItem, at location: BrowseLocation, to newName: String) async throws
}

package actor BrowseOperationService: BrowseOperationServiceProtocol {
    private let fileService: FileOperationServiceProtocol
    private let archiveService: ArchiveServiceProtocol

    package init(
        fileService: FileOperationServiceProtocol = FileOperationService(),
        archiveService: ArchiveServiceProtocol = ArchiveService()
    ) {
        self.fileService = fileService
        self.archiveService = archiveService
    }

    package func copy(
        items: [FileItem],
        from source: BrowseLocation,
        to destination: BrowseLocation,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws {
        switch (source, destination) {
        case (.directory, .directory(let destinationURL)):
            try await fileService.copy(
                sources: items.map(\.url),
                to: destinationURL,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (.directory, .zipArchive(let container, let internalPath)):
            _ = try await copyIntoArchive(
                items: items,
                sourceURLs: items.map(\.url),
                container: container,
                internalPath: internalPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (
            .zipArchive(let container, _),
            .directory(let destinationURL)
        ):
            _ = try await copyFromArchive(
                items: items,
                container: container,
                destination: destinationURL,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (
            .zipArchive(let sourceContainer, _),
            .zipArchive(let destinationContainer, let destinationPath)
        ):
            let temporaryDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            try await archiveService.extract(
                container: sourceContainer,
                paths: try archivePaths(for: items),
                to: temporaryDirectory
            )
            let extractedItems = items.map {
                temporaryDirectory.appendingPathComponent($0.name)
            }
            _ = try await copyIntoArchive(
                items: items,
                sourceURLs: extractedItems,
                container: destinationContainer,
                internalPath: destinationPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        }
    }

    package func move(
        items: [FileItem],
        from source: BrowseLocation,
        to destination: BrowseLocation,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws {
        if source == destination {
            return
        }
        if case .directory = source, case .directory(let destinationURL) = destination {
            try await fileService.move(
                sources: items.map(\.url),
                to: destinationURL,
                onProgress: onProgress,
                onConflict: onConflict
            )
            return
        }

        let transferredItems: [FileItem]
        switch (source, destination) {
        case (.directory, .zipArchive(let container, let internalPath)):
            transferredItems = try await copyIntoArchive(
                items: items,
                sourceURLs: items.map(\.url),
                container: container,
                internalPath: internalPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (.zipArchive(let container, _), .directory(let destinationURL)):
            transferredItems = try await copyFromArchive(
                items: items,
                container: container,
                destination: destinationURL,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (
            .zipArchive(let sourceContainer, _),
            .zipArchive(let destinationContainer, let destinationPath)
        ):
            let temporaryDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            try await archiveService.extract(
                container: sourceContainer,
                paths: try archivePaths(for: items),
                to: temporaryDirectory
            )
            transferredItems = try await copyIntoArchive(
                items: items,
                sourceURLs: items.map { temporaryDirectory.appendingPathComponent($0.name) },
                container: destinationContainer,
                internalPath: destinationPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (.directory, .directory):
            return
        }
        if !transferredItems.isEmpty {
            try await delete(items: transferredItems, from: source, permanently: true)
        }
    }

    package func delete(
        items: [FileItem],
        from source: BrowseLocation,
        permanently: Bool
    ) async throws {
        switch source {
        case .directory:
            if permanently {
                try await fileService.deletePermanently(items: items.map(\.url))
            } else {
                _ = try await fileService.trash(items: items.map(\.url))
            }
        case .zipArchive(let container, _):
            try await archiveService.remove(
                container: container,
                paths: try archivePaths(for: items)
            )
        }
    }

    package func createDirectory(at location: BrowseLocation, name: String) async throws {
        switch location {
        case .directory(let url):
            _ = try await fileService.createFolder(in: url, name: name)
        case .zipArchive(let container, let internalPath):
            try await archiveService.createDirectory(
                container: container,
                internalPath: internalPath,
                name: name
            )
        }
    }

    package func rename(
        item: FileItem,
        at location: BrowseLocation,
        to newName: String
    ) async throws {
        switch location {
        case .directory:
            _ = try await fileService.rename(item: item.url, to: newName)
        case .zipArchive(let container, _):
            guard let path = item.archiveInternalPath else {
                throw FileOperationError.invalidDestination
            }
            try await archiveService.rename(container: container, path: path, newName: newName)
        }
    }

    private func archivePaths(for items: [FileItem]) throws -> [String] {
        try items.map { item in
            guard let path = item.archiveInternalPath else {
                throw FileOperationError.invalidDestination
            }
            return path
        }
    }

    private func copyIntoArchive(
        items: [FileItem],
        sourceURLs: [URL],
        container: URL,
        internalPath: String,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws -> [FileItem] {
        let existingItems = try await archiveService.list(
            container: container,
            internalPath: internalPath,
            showHidden: true
        )
        var existingNames = Set(existingItems.map(\.name))
        var transferredItems: [FileItem] = []

        for (index, pair) in zip(items, sourceURLs).enumerated() {
            let (item, sourceURL) = pair
            var destinationName = item.name
            if existingNames.contains(destinationName) {
                switch await onConflict(
                    .archiveDestinationExists(
                        sourceName: item.name,
                        destinationName: destinationName
                    )
                ) {
                case .skip:
                    reportProgress(index: index, items: items, onProgress: onProgress)
                    continue
                case .overwrite:
                    try await archiveService.remove(
                        container: container,
                        paths: [joinedPath(internalPath, destinationName)]
                    )
                case .rename(let newName):
                    destinationName = newName
                }
            }
            try await archiveService.add(
                container: container,
                internalPath: internalPath,
                source: sourceURL,
                name: destinationName
            )
            existingNames.insert(destinationName)
            transferredItems.append(item)
            reportProgress(index: index, items: items, onProgress: onProgress)
        }
        return transferredItems
    }

    private func copyFromArchive(
        items: [FileItem],
        container: URL,
        destination: URL,
        onProgress: @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws -> [FileItem] {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try await archiveService.extract(
            container: container,
            paths: try archivePaths(for: items),
            to: temporaryDirectory
        )

        var transferredItems: [FileItem] = []
        for (index, item) in items.enumerated() {
            let recorder = ConflictResolutionRecorder()
            try await fileService.copy(
                sources: [temporaryDirectory.appendingPathComponent(item.name)],
                to: destination,
                onProgress: { _ in },
                onConflict: { conflict in
                    let resolution = await onConflict(conflict)
                    recorder.record(resolution)
                    return resolution
                }
            )
            if recorder.resolution != .skip {
                transferredItems.append(item)
            }
            reportProgress(index: index, items: items, onProgress: onProgress)
        }
        return transferredItems
    }

    private func reportProgress(
        index: Int,
        items: [FileItem],
        onProgress: @Sendable (FileOperationProgress) -> Void
    ) {
        onProgress(
            FileOperationProgress(
                totalItems: items.count,
                completedItems: index + 1,
                currentItemName: items[index].name
            )
        )
    }

    private func joinedPath(_ path: String, _ name: String) -> String {
        path.isEmpty ? name : path + "/" + name
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrData-ArchiveTransfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private nonisolated final class ConflictResolutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResolution: ConflictResolution?

    var resolution: ConflictResolution? {
        lock.withLock { storedResolution }
    }

    func record(_ resolution: ConflictResolution) {
        lock.withLock { storedResolution = resolution }
    }
}
