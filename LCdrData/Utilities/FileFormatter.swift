//
//  FileFormatter.swift
//  LCdrData
//
//  Created by Dima Skachkov on 02.04.2026.
//

import Foundation

/// Formatting helpers for file sizes, dates, and other metadata displayed in panels.
enum FileFormatter {

    // MARK: - Size Formatting

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    /// Formats a byte count into a human-readable string (e.g. "4.2 MB").
    static func formatSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "--" }
        return byteCountFormatter.string(fromByteCount: bytes)
    }

    // MARK: - Date Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// Formats a date into "yyyy-MM-dd HH:mm" style.
    static func formatDate(_ date: Date?) -> String {
        guard let date else { return "--" }
        return dateFormatter.string(from: date)
    }

    // MARK: - Kind

    /// Returns a human-readable "kind" string for a file item.
    static func kind(for item: FileItem) -> String {
        if item.isParentDirectory { return "Parent" }
        if item.isSymlink { return "Alias" }
        if item.isDirectory { return "Folder" }

        let ext = item.url.pathExtension.lowercased()
        if ext.isEmpty { return "Document" }
        return ext.uppercased()
    }
}
