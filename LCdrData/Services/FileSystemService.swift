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

    /// Resource keys read for each entry while building its file item.
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
            // contentsOfDirectory(at:) refuses a symlink (ENOTDIR) and, when a
            // path merely passes through one, returns children on the resolved
            // target. Names stay on the URL the caller asked for.
            let contents = try fm.contentsOfDirectory(atPath: url.path).map { name in
                url.appendingPathComponent(name)
            }

            return contents.compactMap { itemURL in
                let resourceValues = try? itemURL.resourceValues(
                    forKeys: Set(resourceKeys)
                )
                if !showHidden && (resourceValues?.isHidden ?? false) {
                    return nil
                }

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
