//
//  FileOperation.swift
//  LCdrData
//
//  Created by Dima Skachkov on 20.04.2026.
//

import Foundation

/// Describes the kind of file operation being performed.
enum FileOperationKind: Sendable, Equatable {
    case copy
    case move
    case delete
    case createFolder
    case rename
}

/// Represents a tracked file operation with its status and progress.
struct FileOperation: Identifiable, Sendable {
    let id: UUID
    let kind: FileOperationKind
    let sourceURLs: [URL]
    let destinationURL: URL?
    var status: FileOperationStatus
    var progress: FileOperationProgress?

    init(
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
    var displayDescription: String {
        let count = sourceURLs.count
        let itemWord = count == 1 ? "item" : "items"
        switch kind {
        case .copy:
            return "Copying \(count) \(itemWord)"
        case .move:
            return "Moving \(count) \(itemWord)"
        case .delete:
            return "Deleting \(count) \(itemWord)"
        case .createFolder:
            return "Creating folder"
        case .rename:
            return "Renaming"
        }
    }
}

/// Status of a file operation.
enum FileOperationStatus: Sendable, Equatable {
    case pending
    case inProgress
    case completed
    case failed(String)
    case cancelled
}
