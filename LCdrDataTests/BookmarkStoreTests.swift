import Testing
import Foundation
@testable import LCdrData

// MARK: - Fake bookmark serializer

/// In-memory bookmark serializer: encodes the URL path as UTF-8 data.
/// Used so tests don't depend on the macOS security-scoped bookmark machinery.
nonisolated final class FakeBookmarkSerializer: BookmarkSerializing, @unchecked Sendable {

    private let lock = NSLock()
    private var staleData: Set<Data> = []

    func bookmarkData(for url: URL) -> Data? {
        return url.path.data(using: .utf8)
    }

    func url(fromBookmarkData data: Data) -> URL? {
        let isStale = lock.withLock { staleData.contains(data) }
        guard !isStale else { return nil }
        guard let path = String(data: data, encoding: .utf8) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func markStale(_ data: Data) {
        lock.withLock { _ = staleData.insert(data) }
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
}
