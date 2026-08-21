import Foundation

/// Formatting helpers for file sizes, dates, and other metadata displayed in panels.
package enum FileFormatter {

    // MARK: - Size Formatting

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    /// Formats a byte count into a human-readable string (e.g. "4.2 MB").
    package static func formatSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "--" }
        return byteCountFormatter.string(fromByteCount: bytes)
    }

    // MARK: - Date Formatting

    private static let defaultDatePattern = "yyyy-MM-dd HH:mm"

    /// Formats a date using the default panel pattern (`yyyy-MM-dd HH:mm`).
    package static func formatDate(_ date: Date?) -> String {
        formatDate(date, format: defaultDatePattern)
    }

    /// Formats a date with an explicit `DateFormatter` pattern string.
    package static func formatDate(_ date: Date?, format pattern: String) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Kind

    /// Returns a human-readable "kind" string for a file item.
    package static func kind(for item: FileItem) -> String {
        if item.isParentDirectory { return "Parent" }
        if item.isSymlink { return "Alias" }
        if item.isDirectory { return "Folder" }

        let ext = item.url.pathExtension.lowercased()
        if ext.isEmpty { return "Document" }
        return ext.uppercased()
    }
}
