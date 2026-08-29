import Foundation
import Models

/// Formatting helpers for file sizes, dates, and other metadata displayed in panels.
package enum FileFormatter {

    // MARK: - Size Formatting

    private static let sizeUnits = ["b", "Kb", "Mb", "Gb", "Tb", "Pb", "Eb"]

    /// Formats a byte count into a compact, space-free string (e.g. "4.2Mb", "512b").
    package static func formatSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "--" }
        if bytes < 1000 { return "\(bytes)b" }

        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1000 && unitIndex < sizeUnits.count - 1 {
            value /= 1000
            unitIndex += 1
        }

        var rounded = (value * 10).rounded() / 10
        if rounded >= 1000 && unitIndex < sizeUnits.count - 1 {
            rounded = (rounded / 1000 * 10).rounded() / 10
            unitIndex += 1
        }
        let text = rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
        return text + sizeUnits[unitIndex]
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

        let ext: String
        if let internalPath = item.archiveInternalPath {
            ext = (internalPath as NSString).pathExtension.lowercased()
        } else {
            ext = item.url.pathExtension.lowercased()
        }
        if ext.isEmpty { return "Document" }
        return ext.uppercased()
    }
}
