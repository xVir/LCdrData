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
        resolve(data).url
    }

    /// Resolves bookmark data and produces a refreshed blob when the original
    /// was stale-but-resolvable. Callers should persist `refreshedData` when
    /// non-nil so subsequent launches don't re-encounter the stale flag.
    nonisolated static func resolve(_ data: Data) -> (url: URL?, refreshedData: Data?) {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return (nil, nil)
        }
        let refreshed: Data? = stale ? bookmarkData(for: url) : nil
        return (url, refreshed)
    }
}
