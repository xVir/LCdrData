import Foundation
@testable import Services
@testable import AppEnvironment

// Shared test doubles, used from four test files across four folders.
// They live in their own module so the per-module test targets do not have
// to depend on each other.

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

    func allBookmarkURLs() -> [URL] {
        lock.withLock { Array(bookmarks.values) }
    }

    func bookmarkCovering(url: URL) -> URL? {
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        return lock.withLock {
            var best: URL?
            for (path, bookmarkURL) in bookmarks {
                if target == path || target.hasPrefix(path + "/") {
                    if (best?.path.count ?? -1) < path.count {
                        best = bookmarkURL
                    }
                }
            }
            return best
        }
    }
}

/// Test activator: records calls; pretends `startAccessing` always succeeds.
nonisolated final class RecordingScopeActivator: SecurityScopeActivating, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var started: [URL] = []
    private(set) var stopped: [URL] = []

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock { started.append(url) }
        return true
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { stopped.append(url) }
    }
}
