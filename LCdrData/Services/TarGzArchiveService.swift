import Foundation
import Models

package actor TarGzArchiveService: ArchiveServiceProtocol {
    /// Headers from the last full read of a container. gzip has no central directory,
    /// so the first listing still streams the archive once; later folders reuse this.
    private var memberIndexes: [String: MemberIndex] = [:]

    package init() {}

    package func list(
        container: URL,
        internalPath: String,
        showHidden: Bool
    ) async throws -> [FileItem] {
        let members = try members(of: container)
        let prefix = normalizedPrefix(internalPath)
        var itemsByName: [String: FileItem] = [:]

        for header in members {
            guard header.path.hasPrefix(prefix) else { continue }
            let remainder = String(header.path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }

            let components = remainder.split(separator: "/", omittingEmptySubsequences: true)
            guard let firstComponent = components.first else { continue }
            let name = String(firstComponent)
            guard showHidden || !name.hasPrefix(".") else { continue }

            let isDirectEntry = components.count == 1
            let isDirectory = !isDirectEntry || header.isDirectory
            let entryPath = prefix + name
            if !itemsByName.keys.contains(name) || isDirectEntry {
                itemsByName[name] = FileItem(
                    archiveContainer: container,
                    internalPath: entryPath,
                    name: name,
                    isDirectory: isDirectory,
                    size: isDirectory ? nil : Int64(clamping: header.size),
                    modificationDate: header.modificationDate,
                    isHidden: name.hasPrefix("."),
                    permissions: header.mode
                )
            }
        }
        return Array(itemsByName.values)
    }

    package func isWritable(container: URL) async -> Bool {
        archiveContainerIsWritable(container)
    }

    package func extract(container: URL, paths: [String], to destination: URL) async throws {
        let members = try members(of: container)
        let maximumEntrySize: UInt64 = 4 * 1024 * 1024 * 1024
        var batches: [(path: String, entries: [TarHeader])] = []

        for requestedPath in paths {
            let path = requestedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try validateArchivePath(path)
            let matching = members.filter { $0.path == path || $0.path.hasPrefix(path + "/") }
            guard !matching.isEmpty else { throw ArchiveServiceError.entryNotFound(path) }
            for entry in matching where entry.size > maximumEntrySize {
                throw ArchiveServiceError.entryTooLarge(entry.path)
            }
            batches.append((path, matching))
        }

        let requiredBytes = batches
            .flatMap(\.entries)
            .reduce(Int64(0)) { partial, entry in
                partial + Int64(clamping: entry.size)
            }
        if let availableBytes = try? destination
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           availableBytes < requiredBytes {
            throw ArchiveServiceError.insufficientSpace
        }

        let reader = try TarGzReader(url: container)
        var remaining = Set(batches.flatMap(\.entries).map(\.path))
        var written: [String: URL] = [:]
        while let header = try reader.next() {
            try Task.checkCancellation()
            guard remaining.contains(header.path) else {
                try reader.discardBody()
                continue
            }
            remaining.remove(header.path)
            guard let batch = batches.first(where: { header.path == $0.path || header.path.hasPrefix($0.path + "/") })
            else {
                try reader.discardBody()
                continue
            }
            let outputURL = try outputURL(for: header, requestedPath: batch.path, destination: destination)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            switch header.kind {
            case .directory:
                try reader.discardBody()
                try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
                written[header.path] = outputURL
            case .symlink:
                try reader.discardBody()
                try writeSymlink(header, to: outputURL, destination: destination)
                written[header.path] = outputURL
            case .hardlink:
                try reader.discardBody()
                written[header.path] = outputURL
            case .file:
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                FileManager.default.createFile(atPath: outputURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: outputURL)
                try reader.copyContent { try handle.write(contentsOf: $0) }
                try handle.close()
                written[header.path] = outputURL
                applyAttributes(header, to: outputURL)
            case .ignored:
                try reader.discardBody()
            }
        }

        for batch in batches {
            for header in batch.entries where header.kind == .hardlink {
                guard let outputURL = written[header.path] else { continue }
                if let existing = written[header.linkPath] {
                    try? FileManager.default.removeItem(at: outputURL)
                    try FileManager.default.linkItem(at: existing, to: outputURL)
                } else if let target = members.first(where: { $0.path == header.linkPath && $0.kind == .file }) {
                    try extractSingleFile(target, from: container, to: outputURL)
                } else {
                    throw ArchiveServiceError.entryNotFound(header.linkPath)
                }
            }
        }
    }

    package func add(container: URL, internalPath: String, sources: [URL]) async throws {
        let basePath = try basePath(internalPath)
        try rewrite(container) { reader, writer in
            try copyMembers(from: reader, to: writer)
            for source in sources {
                let path = basePath.isEmpty ? source.lastPathComponent : basePath + "/" + source.lastPathComponent
                try validateArchivePath(path)
                try appendTree(source, at: path, to: writer)
            }
        }
    }

    package func add(container: URL, internalPath: String, source: URL, name: String) async throws {
        let basePath = try basePath(internalPath)
        guard !name.contains("/") else { throw ArchiveServiceError.unsafePath(name) }
        let path = basePath.isEmpty ? name : basePath + "/" + name
        try validateArchivePath(path)
        try rewrite(container) { reader, writer in
            try copyMembers(from: reader, to: writer)
            try appendTree(source, at: path, to: writer)
        }
    }

    package func remove(container: URL, paths: [String]) async throws {
        let normalizedPaths = try paths.map { path in
            let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            try validateArchivePath(normalized)
            return normalized
        }
        var removed = false
        try rewrite(container) { reader, writer in
            while let header = try reader.next() {
                try Task.checkCancellation()
                let matches = normalizedPaths.contains { path in
                    header.path == path || header.path.hasPrefix(path + "/")
                }
                if matches {
                    removed = true
                    try reader.discardBody()
                    continue
                }
                try transfer(header, from: reader, to: writer)
            }
            guard removed else {
                throw ArchiveServiceError.entryNotFound(normalizedPaths.first ?? "")
            }
        }
    }

    package func createDirectory(container: URL, internalPath: String, name: String) async throws {
        let basePath = try basePath(internalPath)
        guard !name.contains("/") else { throw ArchiveServiceError.unsafePath(name) }
        let path = basePath.isEmpty ? name : basePath + "/" + name
        try validateArchivePath(path)
        try rewrite(container) { reader, writer in
            try copyMembers(from: reader, to: writer)
            try writer.writeDirectory(path: path, mode: 0o755, date: Date())
        }
    }

    package func rename(container: URL, path: String, newName: String) async throws {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        try validateArchivePath(normalizedPath)
        guard !newName.contains("/") else { throw ArchiveServiceError.unsafePath(newName) }
        let parentPath = (normalizedPath as NSString).deletingLastPathComponent
        let renamedPath = parentPath == "." ? newName : parentPath + "/" + newName
        try validateArchivePath(renamedPath)
        var found = false
        try rewrite(container) { reader, writer in
            while let header = try reader.next() {
                try Task.checkCancellation()
                var updated = header
                if header.path == normalizedPath || header.path.hasPrefix(normalizedPath + "/") {
                    found = true
                    let suffix = String(header.path.dropFirst(normalizedPath.count))
                    updated.path = renamedPath + suffix
                }
                try transfer(updated, from: reader, to: writer)
            }
            guard found else { throw ArchiveServiceError.entryNotFound(normalizedPath) }
        }
    }

    private struct MemberIndex: Sendable {
        var size: Int
        var modified: TimeInterval
        var members: [TarHeader]
    }

    /// One sequential pass over the archive, reused until the file's size or mtime changes.
    /// A folder listing only *returns* that folder's children; reaching them still requires
    /// walking every header, because a gzip tar cannot be seeked.
    private func members(of container: URL) throws -> [TarHeader] {
        let key = container.standardizedFileURL.path
        let values = try? container.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize
        let modified = values?.contentModificationDate?.timeIntervalSince1970
        if let size, let modified, let cached = memberIndexes[key],
           cached.size == size, cached.modified == modified {
            return cached.members
        }
        let members = try scan(container)
        if let size, let modified {
            memberIndexes[key] = MemberIndex(size: size, modified: modified, members: members)
        }
        return members
    }

    private func scan(_ container: URL) throws -> [TarHeader] {
        let reader = try TarGzReader(url: container)
        var members: [TarHeader] = []
        while let header = try reader.next() {
            try Task.checkCancellation()
            try reader.discardBody()
            guard !header.path.isEmpty, header.kind != .ignored else { continue }
            guard (try? validateArchivePath(header.path)) != nil else { continue }
            members.append(header)
        }
        return members
    }

    private func rewrite(
        _ container: URL,
        _ transform: (TarGzReader, TarGzWriter) throws -> Void
    ) throws {
        guard archiveContainerIsWritable(container) else { throw ArchiveServiceError.notWritable }
        let temporary = container.deletingLastPathComponent()
            .appendingPathComponent(".LCdrData-\(UUID().uuidString).tar.gz")
        do {
            let reader = try TarGzReader(url: container)
            let writer = try TarGzWriter(url: temporary)
            try transform(reader, writer)
            try writer.finish()
            _ = try FileManager.default.replaceItemAt(container, withItemAt: temporary)
            memberIndexes[container.standardizedFileURL.path] = nil
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func copyMembers(from reader: TarGzReader, to writer: TarGzWriter) throws {
        while let header = try reader.next() {
            try Task.checkCancellation()
            try transfer(header, from: reader, to: writer)
        }
    }

    private func transfer(_ header: TarHeader, from reader: TarGzReader, to writer: TarGzWriter) throws {
        switch header.kind {
        case .file:
            try writer.beginFile(
                path: header.path,
                mode: header.mode,
                date: header.modificationDate,
                size: header.size
            )
            try reader.copyContent { try writer.write($0) }
            try writer.finishContent()
        case .directory:
            try reader.discardBody()
            guard !header.path.isEmpty else { return }
            try writer.writeDirectory(path: header.path, mode: header.mode, date: header.modificationDate)
        case .symlink:
            try reader.discardBody()
            try writer.writeSymlink(
                path: header.path,
                target: header.linkPath,
                mode: header.mode,
                date: header.modificationDate
            )
        case .hardlink:
            try reader.discardBody()
            try writer.writeHardlink(
                path: header.path,
                target: header.linkPath,
                mode: header.mode,
                date: header.modificationDate
            )
        case .ignored:
            try reader.discardBody()
        }
    }

    private func appendTree(_ source: URL, at path: String, to writer: TarGzWriter) throws {
        try validateArchivePath(path)
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        let date = values.contentModificationDate ?? attributes[.modificationDate] as? Date
        if values.isDirectory == true {
            try writer.writeDirectory(path: path, mode: mode, date: date)
            let children = try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            for child in children {
                try appendTree(child, at: path + "/" + child.lastPathComponent, to: writer)
            }
        } else {
            try writer.writeFile(path: path, mode: mode, date: date, from: source)
        }
    }

    private func outputURL(for header: TarHeader, requestedPath: String, destination: URL) throws -> URL {
        let suffix = String(header.path.dropFirst(requestedPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rootName = (requestedPath as NSString).lastPathComponent
        let relative = suffix.isEmpty ? rootName : rootName + "/" + suffix
        try validateArchivePath(relative)
        let outputURL = destination.appendingPathComponent(relative)
        guard outputURL.standardizedFileURL.path.hasPrefix(destination.standardizedFileURL.path + "/")
            || outputURL.standardizedFileURL.path == destination.standardizedFileURL.path
        else {
            throw ArchiveServiceError.unsafePath(header.path)
        }
        return outputURL
    }

    private func writeSymlink(_ header: TarHeader, to outputURL: URL, destination: URL) throws {
        let parent = outputURL.deletingLastPathComponent()
        let resolved = URL(fileURLWithPath: header.linkPath, relativeTo: parent).standardizedFileURL
        let root = destination.standardizedFileURL.path
        guard resolved.path == root || resolved.path.hasPrefix(root + "/") else {
            throw ArchiveServiceError.unsafePath(header.path)
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.createSymbolicLink(atPath: outputURL.path, withDestinationPath: header.linkPath)
    }

    private func extractSingleFile(_ header: TarHeader, from container: URL, to outputURL: URL) throws {
        let reader = try TarGzReader(url: container)
        while let candidate = try reader.next() {
            guard candidate.path == header.path else {
                try reader.discardBody()
                continue
            }
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: outputURL)
            try reader.copyContent { try handle.write(contentsOf: $0) }
            try handle.close()
            applyAttributes(header, to: outputURL)
            return
        }
        throw ArchiveServiceError.entryNotFound(header.path)
    }

    private func applyAttributes(_ header: TarHeader, to url: URL) {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: header.mode]
        if let date = header.modificationDate {
            attributes[.modificationDate] = date
        }
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func basePath(_ internalPath: String) throws -> String {
        let basePath = internalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !basePath.isEmpty {
            try validateArchivePath(basePath)
        }
        return basePath
    }

    private func normalizedPrefix(_ internalPath: String) -> String {
        let trimmed = internalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "" : trimmed + "/"
    }

    private func validateArchivePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !components.contains(".."), !path.isEmpty else {
            throw ArchiveServiceError.unsafePath(path)
        }
    }
}
