import Foundation

/// Remembers the directories the panels were last showing so a relaunch can
/// resume them.
///
/// The window's `PanelSession` is also carried by macOS window restoration, but
/// that only survives when the system decides to restore windows — it is off
/// whenever "Close windows when quitting an application" is enabled, and it is
/// skipped entirely when the app is killed rather than quit (as `tuist run`
/// does). Recording the paths ourselves makes resuming independent of both.
protocol PanelSessionStoring: Sendable {
    func save(leftPath: String, rightPath: String)
    /// The most recently recorded pair, or `nil` before anything has been recorded.
    func loadLastPaths() -> (left: String, right: String)?
}

final class PanelSessionStore: PanelSessionStoring, @unchecked Sendable {

    private static let storageKey = "lastPanelSession"
    private static let leftKey = "left"
    private static let rightKey = "right"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Written as a single dictionary so the two paths can never be persisted
    /// out of step with one another.
    func save(leftPath: String, rightPath: String) {
        defaults.set(
            [Self.leftKey: leftPath, Self.rightKey: rightPath],
            forKey: Self.storageKey
        )
    }

    func loadLastPaths() -> (left: String, right: String)? {
        guard let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String],
              let left = stored[Self.leftKey],
              let right = stored[Self.rightKey],
              !left.isEmpty,
              !right.isEmpty else {
            return nil
        }
        return (left, right)
    }
}
