import Darwin
import Dispatch
import Foundation

/// Watches a directory path for filesystem changes and invokes `onChange` on the main queue (debounced by caller).
final class DirectoryWatcher: @unchecked Sendable {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.xvir.LCdrData.DirectoryWatcher")

    init(path: String, onChange: @escaping @Sendable () -> Void) {
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .revoke],
            queue: queue
        )
        src.setEventHandler {
            DispatchQueue.main.async(execute: onChange)
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

    func cancel() {
        source?.cancel()
        source = nil
    }
}
