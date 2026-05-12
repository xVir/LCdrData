import Foundation

/// Serializes a URL to/from a `Data` blob (the bookmark). Production uses macOS
/// security-scoped bookmarks; tests inject a fake.
protocol BookmarkSerializing: Sendable {
    func bookmarkData(for url: URL) -> Data?
    func url(fromBookmarkData data: Data) -> URL?
}

/// Production serializer backed by the macOS app-scope security bookmark API.
struct SecurityScopedBookmarkSerializer: BookmarkSerializing {
    func bookmarkData(for url: URL) -> Data? {
        BookmarkService.bookmarkData(for: url)
    }

    func url(fromBookmarkData data: Data) -> URL? {
        BookmarkService.url(fromBookmarkData: data)
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

    private func currentMap() -> [String: Data] {
        (defaults.dictionary(forKey: Self.storageKey) as? [String: Data]) ?? [:]
    }
}
