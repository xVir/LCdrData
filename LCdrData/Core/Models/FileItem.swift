import Foundation
import CryptoKit

/// Represents a single file or directory entry in a panel's file listing.
///
/// The `id` is derived deterministically from the file's standardized URL path,
/// so the same file always produces the same identity across reloads. This
/// lets SwiftUI's `List`/`ForEach` recognize rows as updates rather than
/// deletions + insertions, preventing flicker and preserving scroll position.
package nonisolated struct FileItem: Identifiable, Hashable, Sendable {
    package let id: UUID
    package let url: URL
    package let name: String
    package let isDirectory: Bool
    package let size: Int64?
    package let modificationDate: Date?
    package let creationDate: Date?
    package let isHidden: Bool
    package let isSymlink: Bool
    package let isSymlinkToDirectory: Bool
    package let permissions: UInt16
    package let archiveContainer: URL?
    package let archiveInternalPath: String?

    /// A synthetic ".." entry for navigating to the parent directory.
    package let isParentDirectory: Bool

    /// True when activating this row should navigate into a directory —
    /// either it is a real directory, or it is a symlink whose target is one.
    package var isNavigableDirectory: Bool { isDirectory || isSymlinkToDirectory }
    package var isArchive: Bool {
        archiveContainer == nil
            && !isDirectory
            && url.pathExtension.caseInsensitiveCompare("zip") == .orderedSame
    }
    package var isEnterable: Bool { isNavigableDirectory || isArchive }

    package nonisolated init(
        url: URL,
        name: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        creationDate: Date? = nil,
        isHidden: Bool = false,
        isSymlink: Bool = false,
        isSymlinkToDirectory: Bool = false,
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
        self.isSymlinkToDirectory = isSymlinkToDirectory
        self.permissions = permissions
        self.isParentDirectory = isParentDirectory
        self.archiveContainer = nil
        self.archiveInternalPath = nil
    }

    package nonisolated init(
        archiveContainer: URL,
        internalPath: String,
        name: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        creationDate: Date? = nil,
        isHidden: Bool = false,
        permissions: UInt16 = 0,
        isParentDirectory: Bool = false
    ) {
        self.id = Self.stableArchiveID(
            container: archiveContainer,
            internalPath: internalPath,
            isParentDirectory: isParentDirectory
        )
        self.url = archiveContainer
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.isHidden = isHidden
        self.isSymlink = false
        self.isSymlinkToDirectory = false
        self.permissions = permissions
        self.isParentDirectory = isParentDirectory
        self.archiveContainer = archiveContainer
        self.archiveInternalPath = internalPath
    }

    /// Creates a ".." parent directory entry for the given directory URL.
    package nonisolated static func parentEntry(for directoryURL: URL) -> FileItem {
        let parentURL = directoryURL.deletingLastPathComponent()
        return FileItem(
            url: parentURL,
            name: "..",
            isDirectory: true,
            isParentDirectory: true
        )
    }

    package nonisolated static func parentEntry(for location: BrowseLocation) -> FileItem {
        switch location {
        case .directory(let url):
            return parentEntry(for: url)
        case .zipArchive(let container, let internalPath):
            guard !internalPath.isEmpty else {
                return parentEntry(for: container)
            }
            guard case .zipArchive(_, let parentPath) = location.parent else {
                return parentEntry(for: container)
            }
            return FileItem(
                archiveContainer: container,
                internalPath: parentPath,
                name: "..",
                isDirectory: true,
                isParentDirectory: true
            )
        }
    }

    // MARK: - Stable ID

    /// Derives a deterministic UUID from a file URL so that the same file
    /// always gets the same identity across directory reloads.
    private nonisolated static func stableID(for url: URL, isParentDirectory: Bool) -> UUID {
        // Use a prefix to distinguish the ".." entry (which shares a URL
        // with its parent directory) from a regular directory entry.
        let prefix = isParentDirectory ? "parent:" : "file:"
        let key = prefix + url.standardizedFileURL.path
        return stableID(forKey: key)
    }

    private nonisolated static func stableArchiveID(
        container: URL,
        internalPath: String,
        isParentDirectory: Bool
    ) -> UUID {
        let prefix = isParentDirectory ? "parent:" : "zip:"
        return stableID(forKey: prefix + container.standardizedFileURL.path + "!" + internalPath)
    }

    private nonisolated static func stableID(forKey key: String) -> UUID {
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
