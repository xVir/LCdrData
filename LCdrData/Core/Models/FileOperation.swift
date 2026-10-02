import Foundation

/// Describes the kind of file operation being performed.
package enum FileOperationKind: Sendable, Equatable {
    case copy
    case move
    case delete
    case permanentDelete
    case createFolder
    case rename
}

/// Represents a tracked file operation with its status and progress.
package struct FileOperation: Identifiable, Sendable {
    package let id: UUID
    package let kind: FileOperationKind
    package let sourceURLs: [URL]
    package let destinationURL: URL?
    package var status: FileOperationStatus
    package var progress: FileOperationProgress?
    /// Cancel was asked, but the current item cannot be stopped until its write returns.
    package var isFinishingCurrentItem: Bool

    package init(
        id: UUID = UUID(),
        kind: FileOperationKind,
        sourceURLs: [URL],
        destinationURL: URL? = nil,
        status: FileOperationStatus = .pending,
        progress: FileOperationProgress? = nil,
        isFinishingCurrentItem: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.sourceURLs = sourceURLs
        self.destinationURL = destinationURL
        self.status = status
        self.progress = progress
        self.isFinishingCurrentItem = isFinishingCurrentItem
    }

    /// Human-readable description of the operation.
    package var displayDescription: String {
        let count = sourceURLs.count
        let itemWord = count == 1 ? "item" : "items"
        switch kind {
        case .copy:
            return "Copying \(count) \(itemWord)"
        case .move:
            return "Moving \(count) \(itemWord)"
        case .delete:
            return "Deleting \(count) \(itemWord)"
        case .permanentDelete:
            return "Permanently deleting \(count) \(itemWord)"
        case .createFolder:
            return "Creating folder"
        case .rename:
            return "Renaming"
        }
    }

    /// Where the items went, or will go. Copy and move name the destination
    /// folder, trash says "Trash", and a permanent delete names the folder the
    /// items were removed from. A path inside `homePath` is abbreviated with `~`.
    package func locationDescription(
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        switch kind {
        case .copy, .move:
            guard let destinationURL else { return "" }
            return abbreviatedFilePath(destinationURL, homePath: homePath)
        case .delete:
            return "Trash"
        case .permanentDelete:
            let parents = sourceURLs.map { $0.deletingLastPathComponent() }
            let uniqueParents = Set(parents.map(\.path))
            if uniqueParents.count == 1, let parent = parents.first {
                return abbreviatedFilePath(parent, homePath: homePath)
            }
            if uniqueParents.count > 1 {
                return "Multiple folders"
            }
            return ""
        case .createFolder, .rename:
            return ""
        }
    }
}

/// `~/Documents` when `url` is inside `homePath`. A path that only shares a
/// prefix with home — `/Users/media` against `/Users/me` — stays absolute.
private func abbreviatedFilePath(_ url: URL, homePath: String) -> String {
    let path = url.path
    let home = URL(fileURLWithPath: homePath).path
    if path == home { return "~" }
    let prefix = home.hasSuffix("/") ? home : home + "/"
    guard path.hasPrefix(prefix) else { return path }
    return "~/" + path.dropFirst(prefix.count)
}

/// Status of a file operation.
package enum FileOperationStatus: Sendable, Equatable {
    case pending
    case inProgress
    case completed
    case failed(String)
    case cancelled
}

/// Reports progress for a file operation.
package nonisolated struct FileOperationProgress: Sendable {
    package let totalItems: Int
    package let completedItems: Int
    package let currentItemName: String

    package init(totalItems: Int, completedItems: Int, currentItemName: String) {
        self.totalItems = totalItems
        self.completedItems = completedItems
        self.currentItemName = currentItemName
    }

    package var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }
}
