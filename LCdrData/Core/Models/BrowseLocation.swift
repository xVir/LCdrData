import Foundation

package nonisolated enum BrowseLocation: Hashable, Sendable {
    case directory(URL)
    case zipArchive(container: URL, internalPath: String)
    case tarGzArchive(container: URL, internalPath: String)

    package nonisolated var isArchive: Bool {
        archive != nil
    }

    package nonisolated var archive: ArchiveReference? {
        switch self {
        case .directory:
            return nil
        case .zipArchive(let container, let internalPath):
            return ArchiveReference(container: container, internalPath: internalPath, format: .zip)
        case .tarGzArchive(let container, let internalPath):
            return ArchiveReference(container: container, internalPath: internalPath, format: .tarGz)
        }
    }

    /// A location inside the archive at `container`, choosing the format from its name.
    package nonisolated static func archive(container: URL, internalPath: String) -> BrowseLocation {
        if ArchiveFormat(url: container) == .tarGz {
            return .tarGzArchive(container: container, internalPath: internalPath)
        }
        return .zipArchive(container: container, internalPath: internalPath)
    }

    package nonisolated var parent: BrowseLocation {
        switch self {
        case .directory(let url):
            return .directory(url.deletingLastPathComponent())
        case .zipArchive, .tarGzArchive:
            guard let archive else { return self }
            guard !archive.internalPath.isEmpty else {
                return .directory(archive.container.deletingLastPathComponent())
            }
            let parentPath = (archive.internalPath as NSString).deletingLastPathComponent
            return Self.archive(
                container: archive.container,
                internalPath: parentPath == "." ? "" : parentPath
            )
        }
    }

    package nonisolated var persistentDirectory: URL {
        switch self {
        case .directory(let url):
            return url
        case .zipArchive(let container, _), .tarGzArchive(let container, _):
            return container.deletingLastPathComponent()
        }
    }

    package nonisolated var displayPath: String {
        switch self {
        case .directory(let url):
            return url.path
        case .zipArchive(let container, let internalPath),
             .tarGzArchive(let container, let internalPath):
            guard !internalPath.isEmpty else { return container.path }
            return container.path + "/" + internalPath
        }
    }

    package nonisolated var watchURL: URL {
        switch self {
        case .directory(let url):
            return url
        case .zipArchive(let container, _), .tarGzArchive(let container, _):
            return container
        }
    }
}
