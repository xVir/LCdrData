import Foundation

/// Coordinates user-facing sandbox-access requests. Owns single-flight dedup
/// for concurrent callers asking for the same resolved target — the actor
/// guarantees only one presenter invocation per in-flight key.
actor SandboxAccessService {

    private let presenter: AccessPresenter
    private let bookmarkStore: BookmarkStoreProtocol

    private var inFlight: [URL: [CheckedContinuation<URL?, Never>]] = [:]

    init(presenter: AccessPresenter, bookmarkStore: BookmarkStoreProtocol) {
        self.presenter = presenter
        self.bookmarkStore = bookmarkStore
    }

    /// Requests access for the given context. If another request for the same
    /// resolved-target key is already in flight, awaits its result instead of
    /// presenting again. On a successful grant, persists the bookmark.
    func requestAccessIfNeeded(context: AccessRequestContext) async -> URL? {
        let key = context.dedupKey

        if inFlight[key] != nil {
            return await withCheckedContinuation { continuation in
                inFlight[key, default: []].append(continuation)
            }
        }

        // Mark as in-flight before the suspension so concurrent callers dedup.
        inFlight[key] = []
        let granted = await presenter.present(context)

        if let granted {
            bookmarkStore.save(url: granted)
        }

        let awaiters = inFlight[key] ?? []
        inFlight[key] = nil
        for continuation in awaiters {
            continuation.resume(returning: granted)
        }

        return granted
    }

    /// Checks whether a given error indicates a sandbox permission denial.
    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // POSIX permission denied
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 1 { // EPERM
            return true
        }

        // Cocoa file read/write permission errors
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case 257: // NSFileReadNoPermissionError
                return true
            case 513: // NSFileWriteNoPermissionError
                return true
            default:
                break
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionError(underlying)
        }

        return false
    }
}
