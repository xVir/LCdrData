import Testing
import Foundation
@testable import Services

// MARK: - Fake bookmark serializer

/// In-memory bookmark serializer: encodes the URL path as UTF-8 data.
/// Used so tests don't depend on the macOS security-scoped bookmark machinery.
nonisolated final class FakeBookmarkSerializer: BookmarkSerializing, @unchecked Sendable {

    private let lock = NSLock()
    private var staleData: Set<Data> = []
    private var refreshableData: [Data: Data] = [:]

    func bookmarkData(for url: URL) -> Data? {
        return url.path.data(using: .utf8)
    }

    func resolve(_ data: Data) -> (url: URL?, refreshedData: Data?) {
        lock.withLock {
            if staleData.contains(data) {
                return (nil, nil)
            }
            guard let path = String(data: data, encoding: .utf8) else {
                return (nil, nil)
            }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return (url, refreshableData[data])
        }
    }

    func markStale(_ data: Data) {
        lock.withLock { _ = staleData.insert(data) }
    }

    func markStaleButResolvable(_ data: Data, refreshTo refreshed: Data) {
        lock.withLock { refreshableData[data] = refreshed }
    }
}

private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "BookmarkStoreTests-\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

// MARK: - Tests

struct BookmarkStoreTests {

    @Test func resolveReturnsUrlAfterSave() {
        // Arrange
        let serializer = FakeBookmarkSerializer()
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: serializer)
        let url = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)

        // Act
        store.save(url: url)
        let resolved = store.resolve(path: url.path)

        // Assert
        #expect(resolved?.path == url.path)
    }

    @Test func resolveReturnsNilForUnknownPath() {
        // Arrange
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: FakeBookmarkSerializer())

        // Act
        let resolved = store.resolve(path: "/never/saved/here")

        // Assert
        #expect(resolved == nil)
    }

    @Test func resolveReturnsNilForStaleBookmark() {
        // Arrange
        let serializer = FakeBookmarkSerializer()
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: serializer)
        let url = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        store.save(url: url)
        // Simulate the OS deciding the bookmark is stale (e.g., folder moved).
        serializer.markStale(url.path.data(using: .utf8)!)

        // Act
        let resolved = store.resolve(path: url.path)

        // Assert
        #expect(resolved == nil)
    }

    @Test func multiplePathsResolveIndependently() {
        // Arrange
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: FakeBookmarkSerializer())
        let docs = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let downloads = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        store.save(url: docs)
        store.save(url: downloads)

        // Act
        let resolvedDocs = store.resolve(path: docs.path)
        let resolvedDownloads = store.resolve(path: downloads.path)

        // Assert
        #expect(resolvedDocs?.path == docs.path)
        #expect(resolvedDownloads?.path == downloads.path)
    }

    @Test func bookmarkCoveringFindsAncestor() {
        // Arrange
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: FakeBookmarkSerializer())
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        store.save(url: home)

        // Act
        let target = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let covering = store.bookmarkCovering(url: target)

        // Assert
        #expect(covering?.path == home.path)
    }

    @Test func bookmarkCoveringFindsLongestPrefix() {
        // Arrange — two overlapping bookmarks; the more specific one wins.
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: FakeBookmarkSerializer())
        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let backup = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)
        store.save(url: volumes)
        store.save(url: backup)

        // Act
        let target = URL(fileURLWithPath: "/Volumes/Backup/Photos", isDirectory: true)
        let covering = store.bookmarkCovering(url: target)

        // Assert
        #expect(covering?.path == backup.path)
    }

    @Test func bookmarkCoveringReturnsNilWhenNoMatch() {
        // Arrange
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: FakeBookmarkSerializer())
        store.save(url: URL(fileURLWithPath: "/Users/test", isDirectory: true))

        // Act
        let target = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)
        let covering = store.bookmarkCovering(url: target)

        // Assert
        #expect(covering == nil)
    }

    @Test func bookmarkCoveringRequiresFullComponentMatch() {
        // Arrange — guards against a naive `hasPrefix` that would match
        // "/Users/test" against "/Users/test2" — different folder, same prefix.
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: FakeBookmarkSerializer())
        store.save(url: URL(fileURLWithPath: "/Users/test", isDirectory: true))

        // Act
        let target = URL(fileURLWithPath: "/Users/test2/Documents", isDirectory: true)
        let covering = store.bookmarkCovering(url: target)

        // Assert
        #expect(covering == nil)
    }

    @Test func allBookmarkURLsPrunesUnresolvableEntries() {
        // Arrange
        let serializer = FakeBookmarkSerializer()
        let defaults = makeIsolatedDefaults()
        let store = BookmarkStore(defaults: defaults, serializer: serializer)
        let alive = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let dead = URL(fileURLWithPath: "/Volumes/Gone", isDirectory: true)
        store.save(url: alive)
        store.save(url: dead)
        serializer.markStale(dead.path.data(using: .utf8)!)

        // Act
        _ = store.allBookmarkURLs()

        // Assert — dead entry pruned, alive entry preserved
        let stored = (defaults.dictionary(forKey: "bookmarks") as? [String: Data]) ?? [:]
        #expect(stored[alive.path] != nil)
        #expect(stored[dead.path] == nil)
    }

    @Test func allBookmarkURLsRefreshesStaleEntries() {
        // Arrange
        let serializer = FakeBookmarkSerializer()
        let defaults = makeIsolatedDefaults()
        let store = BookmarkStore(defaults: defaults, serializer: serializer)
        let url = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        store.save(url: url)
        let originalBlob = url.path.data(using: .utf8)!
        let refreshedBlob = (url.path + "/refreshed").data(using: .utf8)!
        serializer.markStaleButResolvable(originalBlob, refreshTo: refreshedBlob)

        // Act
        let urls = store.allBookmarkURLs()

        // Assert — URL still resolves
        #expect(urls.first?.path == url.path)

        // Assert — stored blob was overwritten with the refreshed one
        let stored = (defaults.dictionary(forKey: "bookmarks") as? [String: Data]) ?? [:]
        #expect(stored[url.path] == refreshedBlob)
    }

    @Test func allBookmarkURLsReturnsResolvedURLs() {
        // Arrange
        let store = BookmarkStore(defaults: makeIsolatedDefaults(), serializer: FakeBookmarkSerializer())
        let docs = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let downloads = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        store.save(url: docs)
        store.save(url: downloads)

        // Act
        let urls = store.allBookmarkURLs()

        // Assert
        let paths = Set(urls.map(\.path))
        #expect(paths == [docs.path, downloads.path])
    }
}
