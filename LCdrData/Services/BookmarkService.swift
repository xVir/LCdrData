import Foundation

/// Creates and resolves app-scope security bookmarks for sandboxed folder access across launches.
enum BookmarkService {

    /// Returns bookmark data suitable for `UserDefaults`, or nil if creation fails.
    nonisolated static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves bookmark data to a file URL without starting security scope.
    nonisolated static func url(fromBookmarkData data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else { return nil }
        return url
    }
}
