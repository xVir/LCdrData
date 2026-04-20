import Foundation

/// Represents a single file or directory entry in a panel's file listing.
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
        id: UUID = UUID(),
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
        self.id = id
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
}
