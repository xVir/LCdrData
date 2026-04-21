import Foundation
import CryptoKit

/// Represents a single file or directory entry in a panel's file listing.
///
/// The `id` is derived deterministically from the file's standardized URL path,
/// so the same file always produces the same identity across reloads. This
/// lets SwiftUI's `List`/`ForEach` recognize rows as updates rather than
/// deletions + insertions, preventing flicker and preserving scroll position.
struct FileItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let isHidden: Bool
    let isSymlink: Bool
    let permissions: UInt16

    /// A synthetic ".." entry for navigating to the parent directory.
    let isParentDirectory: Bool

    nonisolated init(
        url: URL,
        name: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        creationDate: Date? = nil,
        isHidden: Bool = false,
        isSymlink: Bool = false,
        permissions: UInt16 = 0,
        isParentDirectory: Bool = false
    ) {
        self.id = Self.stableID(for: url, isParentDirectory: isParentDirectory)
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.isHidden = isHidden
        self.isSymlink = isSymlink
        self.permissions = permissions
        self.isParentDirectory = isParentDirectory
    }

    /// Creates a ".." parent directory entry for the given directory URL.
    nonisolated static func parentEntry(for directoryURL: URL) -> FileItem {
        let parentURL = directoryURL.deletingLastPathComponent()
        return FileItem(
            url: parentURL,
            name: "..",
            isDirectory: true,
            isParentDirectory: true
        )
    }

    // MARK: - Stable ID

    /// Derives a deterministic UUID from a file URL so that the same file
    /// always gets the same identity across directory reloads.
    private nonisolated static func stableID(for url: URL, isParentDirectory: Bool) -> UUID {
        // Use a prefix to distinguish the ".." entry (which shares a URL
        // with its parent directory) from a regular directory entry.
        let prefix = isParentDirectory ? "parent:" : "file:"
        let key = prefix + url.standardizedFileURL.path
        let hash = SHA256.hash(data: Data(key.utf8))
        // Build a UUID from the first 16 bytes of the SHA-256 digest.
        let bytes = Array(hash.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
