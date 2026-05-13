import Darwin
import Dispatch
import Foundation

/// A panel's grip on one directory: watches the FD for filesystem changes
/// and debounces those changes before notifying via `onChange`.
///
/// Sessions are short-lived — replaced (not mutated) when the panel navigates
/// to a different URL. Security scope is managed app-wide by
/// `AppEnvironment` from at-launch bookmark activation, not per-session.
final class DirectorySession: @unchecked Sendable {

    let url: URL
    private let debounceInterval: TimeInterval
    private let onChange: @MainActor () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.xvir.LCdrData.DirectorySession")

    private var debounceGeneration: UInt64 = 0
    private var isCancelled: Bool = false

    init(
        url: URL,
        debounceInterval: TimeInterval = 0.28,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.url = url
        self.debounceInterval = debounceInterval
        self.onChange = onChange

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

    /// Stops watching and closes the file descriptor. Idempotent — safe to
    /// call from `deinit` even if the caller already invoked it.
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        source?.cancel()
        source = nil
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
