import Foundation

/// Serializes a URL to/from a `Data` blob (the bookmark). Production uses macOS
/// security-scoped bookmarks; tests inject a fake.
protocol BookmarkSerializing: Sendable {
    func bookmarkData(for url: URL) -> Data?
    func resolve(_ data: Data) -> (url: URL?, refreshedData: Data?)
}

extension BookmarkSerializing {
    func url(fromBookmarkData data: Data) -> URL? {
        resolve(data).url
    }
}

/// Production serializer backed by the macOS app-scope security bookmark API.
struct SecurityScopedBookmarkSerializer: BookmarkSerializing {
    func bookmarkData(for url: URL) -> Data? {
        BookmarkService.bookmarkData(for: url)
    }

    func resolve(_ data: Data) -> (url: URL?, refreshedData: Data?) {
        BookmarkService.resolve(data)
    }
}

/// Persists bookmarks keyed by path. Decoupled from window management.
protocol BookmarkStoreProtocol: Sendable {
    func save(url: URL)
    func resolve(path: String) -> URL?
}

final class BookmarkStore: BookmarkStoreProtocol, @unchecked Sendable {

    private static let storageKey = "bookmarks"

    private let defaults: UserDefaults
    private let serializer: BookmarkSerializing
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        serializer: BookmarkSerializing = SecurityScopedBookmarkSerializer()
    ) {
        self.defaults = defaults
        self.serializer = serializer
    }

    func save(url: URL) {
        guard let data = serializer.bookmarkData(for: url) else { return }
        lock.withLock {
            var map = currentMap()
            map[url.path] = data
            defaults.set(map, forKey: Self.storageKey)
        }
    }

    func resolve(path: String) -> URL? {
        let data: Data? = lock.withLock { currentMap()[path] }
        guard let data else { return nil }
        return serializer.url(fromBookmarkData: data)
    }

    func allBookmarkURLs() -> [URL] {
        let map = lock.withLock { currentMap() }
        var refreshes: [String: Data] = [:]
        var doomedPaths: [String] = []
        var urls: [URL] = []
        for (path, data) in map {
            let resolved = serializer.resolve(data)
            guard let url = resolved.url else {
                doomedPaths.append(path)
                continue
            }
            urls.append(url)
            if let refreshed = resolved.refreshedData {
                refreshes[path] = refreshed
            }
        }
        if !refreshes.isEmpty || !doomedPaths.isEmpty {
            lock.withLock {
                var current = currentMap()
                for (path, data) in refreshes {
                    current[path] = data
                }
                for path in doomedPaths {
                    current.removeValue(forKey: path)
                }
                defaults.set(current, forKey: Self.storageKey)
            }
        }
        return urls
    }

    func bookmarkCovering(url: URL) -> URL? {
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        let map = lock.withLock { currentMap() }

        var bestPath: String?
        for storedPath in map.keys {
            if target == storedPath || target.hasPrefix(storedPath + "/") {
                if (bestPath?.count ?? -1) < storedPath.count {
                    bestPath = storedPath
                }
            }
        }

        guard let bestPath else { return nil }
        return resolve(path: bestPath)
    }

    private func currentMap() -> [String: Data] {
        (defaults.dictionary(forKey: Self.storageKey) as? [String: Data]) ?? [:]
    }
}
