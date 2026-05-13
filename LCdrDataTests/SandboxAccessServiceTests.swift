import Testing
import Foundation
@testable import LCdrData

// MARK: - Fakes

/// Test presenter: returns a configured URL (or nil) without touching AppKit.
nonisolated final class FakeAccessPresenter: AccessPresenter, @unchecked Sendable {

    private let lock = NSLock()
    private var queuedResults: [URL?]
    private(set) var presentedContexts: [AccessRequestContext] = []

    init(result: URL?) {
        self.queuedResults = [result]
    }

    init(results: [URL?]) {
        self.queuedResults = results
    }

    func present(_ context: AccessRequestContext) async -> URL? {
        lock.withLock {
            presentedContexts.append(context)
            return queuedResults.isEmpty ? nil : queuedResults.removeFirst()
        }
    }
}

/// Test bookmark store: in-memory, records saves.
nonisolated final class FakeBookmarkStore: BookmarkStoreProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var bookmarks: [String: URL] = [:]
    private(set) var savedURLs: [URL] = []

    func save(url: URL) {
        lock.withLock {
            bookmarks[url.path] = url
            savedURLs.append(url)
        }
    }

    func resolve(path: String) -> URL? {
        lock.withLock { bookmarks[path] }
    }
}

// MARK: - Tests

struct SandboxAccessServiceTests {

    @Test func requestAccessCancelReturnsNilWithoutPersisting() async {
        // Arrange
        let presenter = FakeAccessPresenter(result: nil)
        let store = FakeBookmarkStore()
        let service = SandboxAccessService(presenter: presenter, bookmarkStore: store)
        let target = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)

        // Act
        let result = await service.requestAccessIfNeeded(
            context: .manualGrant(suggestedURL: target)
        )

        // Assert
        #expect(result == nil)
        #expect(store.savedURLs.isEmpty)
    }

    @Test func requestAccessGrantPersistsBookmark() async {
        // Arrange
        let granted = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)
        let presenter = FakeAccessPresenter(result: granted)
        let store = FakeBookmarkStore()
        let service = SandboxAccessService(presenter: presenter, bookmarkStore: store)

        // Act
        let result = await service.requestAccessIfNeeded(
            context: .manualGrant(suggestedURL: granted)
        )

        // Assert
        #expect(result?.path == granted.path)
        #expect(store.savedURLs.map(\.path) == [granted.path])
    }

    @Test func requestAccessInFlightDedupYieldsOneCallAndSharedResult() async {
        // Arrange — second concurrent call for the same resolved target must
        // not invoke the presenter a second time; both awaiters get the
        // first call's outcome.
        let granted = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)
        let presenter = SlowFakeAccessPresenter(result: granted)
        let store = FakeBookmarkStore()
        let service = SandboxAccessService(presenter: presenter, bookmarkStore: store)
        let target = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)

        // Act — fire two concurrent requests for the same target.
        async let first = service.requestAccessIfNeeded(
            context: .manualGrant(suggestedURL: target)
        )
        async let second = service.requestAccessIfNeeded(
            context: .manualGrant(suggestedURL: target)
        )
        let (firstResult, secondResult) = await (first, second)

        // Assert — only one presenter invocation; both awaiters got the URL.
        #expect(presenter.presentCount == 1)
        #expect(firstResult?.path == granted.path)
        #expect(secondResult?.path == granted.path)
    }
}

/// Presenter that suspends until released, so we can pile up awaiters before
/// the first call resolves. Used to exercise single-flight dedup.
nonisolated final class SlowFakeAccessPresenter: AccessPresenter, @unchecked Sendable {

    private let lock = NSLock()
    private var _presentCount: Int = 0
    private let result: URL?

    init(result: URL?) {
        self.result = result
    }

    var presentCount: Int {
        lock.withLock { _presentCount }
    }

    func present(_ context: AccessRequestContext) async -> URL? {
        lock.withLock { _presentCount += 1 }
        // Yield enough to let the second concurrent caller join as an awaiter
        // before this one resolves.
        for _ in 0..<10 { await Task.yield() }
        return result
    }
}
