import Foundation
import Models
import ZIPFoundation

package nonisolated protocol ArchiveServiceProtocol: Sendable {
    func list(container: URL, internalPath: String, showHidden: Bool) async throws -> [FileItem]
    func extract(container: URL, paths: [String], to destination: URL) async throws
    func add(container: URL, internalPath: String, sources: [URL]) async throws
    func add(container: URL, internalPath: String, source: URL, name: String) async throws
    func remove(container: URL, paths: [String]) async throws
    func createDirectory(container: URL, internalPath: String, name: String) async throws
    func rename(container: URL, path: String, newName: String) async throws
    func isWritable(container: URL) async -> Bool
}

package extension ArchiveServiceProtocol {
    func add(container: URL, internalPath: String, source: URL, name: String) async throws {
        guard name == source.lastPathComponent else {
            throw ArchiveServiceError.unsafePath(name)
        }
        try await add(container: container, internalPath: internalPath, sources: [source])
    }
}

package enum ArchiveServiceError: Error, Equatable, Sendable {
    case entryNotFound(String)
    case unsafePath(String)
    case notWritable
    case unreadable
    case entryTooLarge(String)
    case insufficientSpace
}

package actor ArchiveService: ArchiveServiceProtocol {
    package init() {}

    package func list(
        container: URL,
        internalPath: String,
        showHidden: Bool
    ) async throws -> [FileItem] {
        let archive: Archive
        do {
            archive = try Archive(url: container, accessMode: .read)
        } catch {
            throw ArchiveServiceError.unreadable
        }
        let prefix = internalPath.isEmpty ? "" : internalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        var itemsByName: [String: FileItem] = [:]

        for entry in archive {
            guard entry.path.hasPrefix(prefix) else { continue }
            let remainder = String(entry.path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }

            let components = remainder.split(separator: "/", omittingEmptySubsequences: true)
            guard let firstComponent = components.first else { continue }
            let name = String(firstComponent)
            guard showHidden || !name.hasPrefix(".") else { continue }

            let isDirectEntry = components.count == 1
            let isDirectory = !isDirectEntry || entry.type == .directory
            let entryPath = prefix + name

            if !itemsByName.keys.contains(name) || isDirectEntry {
                let attributes = entry.fileAttributes
                itemsByName[name] = FileItem(
                    archiveContainer: container,
                    internalPath: entryPath,
                    name: name,
                    isDirectory: isDirectory,
                    size: isDirectory ? nil : Int64(clamping: entry.uncompressedSize),
                    modificationDate: attributes[.modificationDate] as? Date,
                    isHidden: name.hasPrefix("."),
                    permissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
                )
            }
        }

        return Array(itemsByName.values)
    }

    package func isWritable(container: URL) async -> Bool {
        isWritableOnDisk(container)
    }

    private func isWritableOnDisk(_ container: URL) -> Bool {
        let fileManager = FileManager.default
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: container.path),
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            permissions & 0o222 != 0
        else {
            return false
        }
        return fileManager.isWritableFile(atPath: container.path)
    }

    package func extract(container: URL, paths: [String], to destination: URL) async throws {
        let archive = try Archive(url: container, accessMode: .read)
        let maximumEntrySize = UInt64(4) * 1024 * 1024 * 1024
        var batches: [(path: String, entries: [Entry])] = []

        for requestedPath in paths {
            let path = requestedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try validateArchivePath(path)
            let matchingEntries = archive.filter { entry in
                entry.path == path || entry.path.hasPrefix(path + "/")
            }
            guard !matchingEntries.isEmpty else {
                throw ArchiveServiceError.entryNotFound(path)
            }
            for entry in matchingEntries where UInt64(entry.uncompressedSize) > maximumEntrySize {
                throw ArchiveServiceError.entryTooLarge(entry.path)
            }
            batches.append((path, matchingEntries))
        }

        let requiredBytes = batches
            .flatMap(\.entries)
            .reduce(Int64(0)) { partial, entry in
                partial + Int64(clamping: entry.uncompressedSize)
            }
        if let availableBytes = try? destination
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           availableBytes < requiredBytes {
            throw ArchiveServiceError.insufficientSpace
        }

        for batch in batches {
            let path = batch.path
            let matchingEntries = batch.entries
            let rootName = (path as NSString).lastPathComponent
            for entry in matchingEntries {
                let suffix = String(entry.path.dropFirst(path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let relativeOutputPath = suffix.isEmpty ? rootName : rootName + "/" + suffix
                try validateArchivePath(relativeOutputPath)
                let outputURL = destination.appendingPathComponent(relativeOutputPath)
                guard outputURL.standardizedFileURL.path.hasPrefix(
                    destination.standardizedFileURL.path + "/"
                ) else {
                    throw ArchiveServiceError.unsafePath(entry.path)
                }
                _ = try archive.extract(entry, to: outputURL)
            }
        }
    }

    package func add(container: URL, internalPath: String, sources: [URL]) async throws {
        guard isWritableOnDisk(container) else { throw ArchiveServiceError.notWritable }
        let archive = try Archive(url: container, accessMode: .update)
        let basePath = internalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !basePath.isEmpty {
            try validateArchivePath(basePath)
        }

        for source in sources {
            let path = basePath.isEmpty
                ? source.lastPathComponent
                : basePath + "/" + source.lastPathComponent
            try addItem(source, at: path, to: archive)
        }
    }

    package func add(
        container: URL,
        internalPath: String,
        source: URL,
        name: String
    ) async throws {
        guard isWritableOnDisk(container) else { throw ArchiveServiceError.notWritable }
        let basePath = internalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !basePath.isEmpty {
            try validateArchivePath(basePath)
        }
        guard !name.contains("/") else {
            throw ArchiveServiceError.unsafePath(name)
        }
        let path = basePath.isEmpty ? name : basePath + "/" + name
        let archive = try Archive(url: container, accessMode: .update)
        try addItem(source, at: path, to: archive)
    }

    package func remove(container: URL, paths: [String]) async throws {
        guard isWritableOnDisk(container) else { throw ArchiveServiceError.notWritable }
        let archive = try Archive(url: container, accessMode: .update)
        let normalizedPaths = try paths.map { path in
            let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try validateArchivePath(normalized)
            return normalized
        }
        let entryPaths = archive
            .map(\.path)
            .filter { entryPath in
                normalizedPaths.contains { path in
                    entryPath == path || entryPath.hasPrefix(path + "/")
                }
            }
            .sorted(by: >)

        guard !entryPaths.isEmpty else {
            throw ArchiveServiceError.entryNotFound(normalizedPaths.first ?? "")
        }
        for entryPath in entryPaths {
            guard let entry = archive[entryPath] else { continue }
            try archive.remove(entry)
        }
    }

    package func createDirectory(container: URL, internalPath: String, name: String) async throws {
        guard isWritableOnDisk(container) else { throw ArchiveServiceError.notWritable }
        let basePath = internalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = basePath.isEmpty ? name : basePath + "/" + name
        try validateArchivePath(path)
        let archive = try Archive(url: container, accessMode: .update)
        try archive.addEntry(
            with: path,
            type: .directory,
            uncompressedSize: Int64(0),
            provider: { (_: Int64, _: Int) in Data() }
        )
    }

    package func rename(container: URL, path: String, newName: String) async throws {
        guard isWritableOnDisk(container) else { throw ArchiveServiceError.notWritable }
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        try validateArchivePath(normalizedPath)
        guard !newName.contains("/") else {
            throw ArchiveServiceError.unsafePath(newName)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LCdrData-ArchiveRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try await extract(container: container, paths: [normalizedPath], to: temporaryDirectory)
        let extractedItem = temporaryDirectory.appendingPathComponent(
            (normalizedPath as NSString).lastPathComponent
        )
        let parentPath = (normalizedPath as NSString).deletingLastPathComponent
        let renamedPath = parentPath == "." ? newName : parentPath + "/" + newName
        try validateArchivePath(renamedPath)

        do {
            let archive = try Archive(url: container, accessMode: .update)
            try addItem(extractedItem, at: renamedPath, to: archive)
        }
        try await remove(container: container, paths: [normalizedPath])
    }

    private func addItem(_ source: URL, at path: String, to archive: Archive) throws {
        try validateArchivePath(path)
        try archive.addEntry(with: path, fileURL: source, compressionMethod: .deflate)

        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { return }
        let children = try FileManager.default.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for child in children {
            try addItem(child, at: path + "/" + child.lastPathComponent, to: archive)
        }
    }

    private func validateArchivePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !components.contains(".."), !path.isEmpty else {
            throw ArchiveServiceError.unsafePath(path)
        }
    }
}
