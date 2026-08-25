import Foundation

package nonisolated enum BrowseLocation: Hashable, Sendable {
    case directory(URL)
    case zipArchive(container: URL, internalPath: String)

    package nonisolated var isArchive: Bool {
        if case .zipArchive = self { return true }
        return false
    }

    package nonisolated var parent: BrowseLocation {
        switch self {
        case .directory(let url):
            return .directory(url.deletingLastPathComponent())
        case .zipArchive(let container, let internalPath):
            guard !internalPath.isEmpty else {
                return .directory(container.deletingLastPathComponent())
            }
            let parentPath = (internalPath as NSString).deletingLastPathComponent
            return .zipArchive(container: container, internalPath: parentPath == "." ? "" : parentPath)
        }
    }

    package nonisolated var persistentDirectory: URL {
        switch self {
        case .directory(let url):
            return url
        case .zipArchive(let container, _):
            return container.deletingLastPathComponent()
        }
    }

    package nonisolated var displayPath: String {
        switch self {
        case .directory(let url):
            return url.path
        case .zipArchive(let container, let internalPath):
            guard !internalPath.isEmpty else { return container.path }
            return container.path + "/" + internalPath
        }
    }

    package nonisolated var watchURL: URL {
        switch self {
        case .directory(let url):
            return url
        case .zipArchive(let container, _):
            return container
        }
    }
}
