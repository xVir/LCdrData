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

    package init(
        id: UUID = UUID(),
        kind: FileOperationKind,
        sourceURLs: [URL],
        destinationURL: URL? = nil,
        status: FileOperationStatus = .pending,
        progress: FileOperationProgress? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceURLs = sourceURLs
        self.destinationURL = destinationURL
        self.status = status
        self.progress = progress
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
package struct FileOperationProgress: Sendable {
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
