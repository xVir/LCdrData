import Testing
import Foundation
@testable import LCdrData

@MainActor
struct AppEnvironmentTests {

    @Test func makeFreshSessionUsesHomeWhenNoFrontmostState() {
        // Arrange
        let env = AppEnvironment()

        // Act
        let session = env.makeFreshSession()

        // Assert
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(session.leftPath == home)
        #expect(session.rightPath == home)
    }

    @Test func makeFreshSessionCopiesFromFrontmostState() {
        // Arrange
        let env = AppEnvironment()
        let frontmost = AppState(
            leftDirectory: URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true),
            rightDirectory: URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        )
        env.mostRecentAppState = frontmost

        // Act
        let session = env.makeFreshSession()

        // Assert
        #expect(session.leftPath == "/Users/test/Documents")
        #expect(session.rightPath == "/Users/test/Downloads")

        _ = frontmost  // keep alive — mostRecentAppState is weak
    }
}
