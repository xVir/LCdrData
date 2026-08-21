import Foundation
import Models

/// Protocol defining file system operations for directory listing and metadata.
/// Using a protocol enables dependency injection and testability.
package nonisolated protocol FileSystemServiceProtocol: Sendable {
    /// Lists the contents of a directory, returning FileItem representations.
    func listDirectory(at url: URL, showHidden: Bool) async throws -> [FileItem]
}

/// Concrete implementation of FileSystemServiceProtocol using Foundation's FileManager.
package nonisolated final class FileSystemService: FileSystemServiceProtocol, Sendable {
    package init() {}

    /// Resource keys to pre-fetch for performance during directory listing.
    private nonisolated static let resourceKeys: [URLResourceKey] = [
        .nameKey,
        .isDirectoryKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .isHiddenKey,
        .isSymbolicLinkKey
    ]

    package func listDirectory(at url: URL, showHidden: Bool) async throws -> [FileItem] {
        let resourceKeys = Self.resourceKeys

        // Use a detached task to run on a background thread, using a local FileManager.
        return try await Task.detached {
            let fm = FileManager()
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: showHidden ? [] : [.skipsHiddenFiles]
            )

            return contents.map { itemURL in
                let resourceValues = try? itemURL.resourceValues(
                    forKeys: Set(resourceKeys)
                )

                let isSymlink = resourceValues?.isSymbolicLink ?? false
                var isSymlinkToDirectory = false
                if isSymlink {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: itemURL.path, isDirectory: &isDir) {
                        isSymlinkToDirectory = isDir.boolValue
                    }
                }

                return FileItem(
                    url: itemURL,
                    name: resourceValues?.name ?? itemURL.lastPathComponent,
                    isDirectory: resourceValues?.isDirectory ?? false,
                    size: resourceValues?.fileSize.map { Int64($0) },
                    modificationDate: resourceValues?.contentModificationDate,
                    creationDate: resourceValues?.creationDate,
                    isHidden: resourceValues?.isHidden ?? false,
                    isSymlink: isSymlink,
                    isSymlinkToDirectory: isSymlinkToDirectory,
                    permissions: 0 // Detailed permissions require stat() — deferred
                )
            }
        }.value
    }
}
