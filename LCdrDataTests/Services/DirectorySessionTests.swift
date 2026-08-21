import Testing
import Foundation
@testable import Core
@testable import Services

@MainActor
struct DirectorySessionTests {

    /// Smoke integration test: creating a file inside a tmp directory under
    /// observation eventually triggers `onChange`. Uses a short debounce
    /// interval so the test is fast.
    @Test func firesOnChangeAfterFilesystemMutation() async throws {
        // Arrange — tmp dir owned by this test
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(
            "DirectorySessionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let signalled = DirectorySessionSignal()
        let session = DirectorySession(
            url: tmpDir,
            debounceInterval: 0.05,
            onChange: { signalled.flag() }
        )
        defer { session.cancel() }

        // Act — write a file inside the watched directory
        try Data().write(to: tmpDir.appendingPathComponent("touched"))

        // Assert — signal fires within a reasonable budget
        let fired = await signalled.wait(timeout: .seconds(2))
        #expect(fired, "DirectorySession.onChange should fire after a filesystem mutation")
    }
}

/// A simple "did the callback fire?" signal that can be awaited from a test.
@MainActor
private final class DirectorySessionSignal {
    private var fired = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func flag() {
        fired = true
        let waiters = continuations
        continuations = []
        for c in waiters { c.resume() }
    }

    /// Returns true if the signal fired within the timeout, false on timeout.
    func wait(timeout: Duration) async -> Bool {
        if fired { return true }

        let waitTask: Task<Void, Never> = Task {
            await withCheckedContinuation { continuation in
                self.continuations.append(continuation)
            }
        }

        let timeoutTask: Task<Void, Never> = Task {
            try? await Task.sleep(for: timeout)
        }

        await Task.yield()

        // Whichever finishes first wins.
        let _ = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await waitTask.value; return true }
            group.addTask { await timeoutTask.value; return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        waitTask.cancel()
        timeoutTask.cancel()

        return fired
    }
}
