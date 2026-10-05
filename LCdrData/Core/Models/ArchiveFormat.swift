import Foundation

/// A container format the app can browse as a location.
package nonisolated enum ArchiveFormat: Hashable, Sendable {
    case zip
    case tarGz

    /// Recognizes `.zip`, `.tar.gz`, and `.tgz`. Plain `.tar` is not included.
    package init?(url: URL) {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            self = .tarGz
        } else if url.pathExtension.lowercased() == "zip" {
            self = .zip
        } else {
            return nil
        }
    }
}

/// The archive file and path inside it for a location that is not a directory.
package nonisolated struct ArchiveReference: Hashable, Sendable {
    package var container: URL
    package var internalPath: String
    package var format: ArchiveFormat
}
