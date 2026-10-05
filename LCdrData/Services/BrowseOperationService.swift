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
        onProgress: @escaping @Sendable (FileOperationProgress) -> Void,
        onConflict: @Sendable (FileConflict) async -> ConflictResolution
    ) async throws

    func delete(
        items: [FileItem],
        from source: BrowseLocation,
        permanently: Bool,
        onProgress: @escaping @Sendable (FileOperationProgress) -> Void
    ) async throws
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
        switch (source.archive, destination.archive) {
        case (nil, nil):
            guard case .directory(let destinationURL) = destination else { return }
            try await fileService.copy(
                sources: items.map(\.url),
                to: destinationURL,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (nil, let destinationArchive?):
            _ = try await copyIntoArchive(
                items: items,
                sourceURLs: items.map(\.url),
                container: destinationArchive.container,
                internalPath: destinationArchive.internalPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (let sourceArchive?, nil):
            guard case .directory(let destinationURL) = destination else { return }
            _ = try await copyFromArchive(
                items: items,
                container: sourceArchive.container,
                destination: destinationURL,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (let sourceArchive?, let destinationArchive?):
            let temporaryDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            try await archiveService.extract(
                container: sourceArchive.container,
                paths: try archivePaths(for: items),
                to: temporaryDirectory
            )
            let extractedItems = items.map {
                temporaryDirectory.appendingPathComponent($0.name)
            }
            _ = try await copyIntoArchive(
                items: items,
                sourceURLs: extractedItems,
                container: destinationArchive.container,
                internalPath: destinationArchive.internalPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        }
    }

    package func move(
        items: [FileItem],
        from source: BrowseLocation,
        to destination: BrowseLocation,
        onProgress: @escaping @Sendable (FileOperationProgress) -> Void,
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
        switch (source.archive, destination.archive) {
        case (nil, let destinationArchive?):
            transferredItems = try await copyIntoArchive(
                items: items,
                sourceURLs: items.map(\.url),
                container: destinationArchive.container,
                internalPath: destinationArchive.internalPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (let sourceArchive?, nil):
            guard case .directory(let destinationURL) = destination else { return }
            transferredItems = try await copyFromArchive(
                items: items,
                container: sourceArchive.container,
                destination: destinationURL,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (let sourceArchive?, let destinationArchive?):
            let temporaryDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            try await archiveService.extract(
                container: sourceArchive.container,
                paths: try archivePaths(for: items),
                to: temporaryDirectory
            )
            transferredItems = try await copyIntoArchive(
                items: items,
                sourceURLs: items.map { temporaryDirectory.appendingPathComponent($0.name) },
                container: destinationArchive.container,
                internalPath: destinationArchive.internalPath,
                onProgress: onProgress,
                onConflict: onConflict
            )
        case (nil, nil):
            return
        }
        if !transferredItems.isEmpty {
            try await delete(
                items: transferredItems,
                from: source,
                permanently: true,
                onProgress: onProgress
            )
        }
    }

    package func delete(
        items: [FileItem],
        from source: BrowseLocation,
        permanently: Bool,
        onProgress: @escaping @Sendable (FileOperationProgress) -> Void
    ) async throws {
        if let archive = source.archive {
            let paths = try archivePaths(for: items)
            for (index, path) in paths.enumerated() {
                try Task.checkCancellation()
                try await archiveService.remove(container: archive.container, paths: [path])
                onProgress(FileOperationProgress(
                    totalItems: paths.count,
                    completedItems: index + 1,
                    currentItemName: (path as NSString).lastPathComponent
                ))
            }
        } else if permanently {
            try await fileService.deletePermanently(items: items.map(\.url), onProgress: onProgress)
        } else {
            _ = try await fileService.trash(items: items.map(\.url), onProgress: onProgress)
        }
    }

    package func createDirectory(at location: BrowseLocation, name: String) async throws {
        if let archive = location.archive {
            try await archiveService.createDirectory(
                container: archive.container,
                internalPath: archive.internalPath,
                name: name
            )
        } else if case .directory(let url) = location {
            _ = try await fileService.createFolder(in: url, name: name)
        }
    }

    package func rename(
        item: FileItem,
        at location: BrowseLocation,
        to newName: String
    ) async throws {
        if let archive = location.archive {
            guard let path = item.archiveInternalPath else {
                throw FileOperationError.invalidDestination
            }
            try await archiveService.rename(container: archive.container, path: path, newName: newName)
        } else {
            _ = try await fileService.rename(item: item.url, to: newName)
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
            try Task.checkCancellation()
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
            try Task.checkCancellation()
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
