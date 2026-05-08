import Darwin
import Dispatch
import Foundation

/// A panel's grip on one directory: while the session exists it holds
/// security-scoped access to the URL, watches the FD for filesystem changes,
/// and debounces those changes before notifying via `onChange`.
///
/// Sessions are short-lived — replaced (not mutated) when the panel navigates
/// to a different URL. `deinit` releases the security scope and cancels the
/// underlying watcher.
final class DirectorySession: @unchecked Sendable {

    let url: URL
    private let debounceInterval: TimeInterval
    private let onChange: @MainActor () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.xvir.LCdrData.DirectorySession")

    private var debounceGeneration: UInt64 = 0
    private var hasSecurityScope: Bool = false
    private var isCancelled: Bool = false

    init(
        url: URL,
        debounceInterval: TimeInterval = 0.28,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.debounceInterval = debounceInterval
        self.onChange = onChange

        // Acquire security-scoped access for the duration of the session.
        // `startAccessingSecurityScopedResource()` returns false for URLs that
        // don't need a scope (e.g. files inside the app's container) — that's
        // fine; we just remember whether we own a scope to release.
        if url.startAccessingSecurityScopedResource() {
            hasSecurityScope = true
        }

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .revoke],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.scheduleDebouncedNotification()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        src.resume()
        source = src
    }

    deinit {
        cancel()
    }

    /// Stops watching, closes the file descriptor, and releases security scope.
    /// Idempotent — safe to call from `deinit` even if the caller already
    /// invoked it.
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        source?.cancel()
        source = nil
        if hasSecurityScope {
            url.stopAccessingSecurityScopedResource()
            hasSecurityScope = false
        }
    }

    private func scheduleDebouncedNotification() {
        queue.async { [weak self] in
            guard let self else { return }
            self.debounceGeneration &+= 1
            let token = self.debounceGeneration
            let interval = self.debounceInterval
            let onChange = self.onChange
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !self.isCancelled,
                      token == self.debounceGeneration else { return }
                onChange()
            }
        }
    }
}
