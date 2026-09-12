import Foundation

/// A window's panels as they should come back on the next launch: the two
/// directories, the tabs open in each panel, and which tab was in front.
package struct PanelSessionSnapshot: Codable, Equatable, Sendable {
    package let leftPath: String
    package let rightPath: String
    package let leftTabPaths: [String]
    package let rightTabPaths: [String]
    package let leftActiveTabIndex: Int
    package let rightActiveTabIndex: Int

    package init(
        leftPath: String,
        rightPath: String,
        leftTabPaths: [String] = [],
        rightTabPaths: [String] = [],
        leftActiveTabIndex: Int = 0,
        rightActiveTabIndex: Int = 0
    ) {
        self.leftPath = leftPath
        self.rightPath = rightPath
        // A snapshot always describes at least the panel's own directory, so a
        // reader never has to decide what an empty tab list means.
        self.leftTabPaths = leftTabPaths.isEmpty ? [leftPath] : leftTabPaths
        self.rightTabPaths = rightTabPaths.isEmpty ? [rightPath] : rightTabPaths
        self.leftActiveTabIndex = max(0, leftActiveTabIndex)
        self.rightActiveTabIndex = max(0, rightActiveTabIndex)
    }
}

/// Remembers what the panels were showing so a relaunch can resume them.
///
/// The window's `PanelSession` is also carried by macOS window restoration, but
/// that only survives when the system decides to restore windows — it is off
/// whenever "Close windows when quitting an application" is enabled, and it is
/// skipped entirely when the app is killed rather than quit (as `tuist run`
/// does). Recording the state ourselves makes resuming independent of both.
package protocol PanelSessionStoring: Sendable {
    func save(_ snapshot: PanelSessionSnapshot)
    /// The most recently recorded snapshot, or `nil` before anything has been recorded.
    func loadLastSession() -> PanelSessionSnapshot?
}

package final class PanelSessionStore: PanelSessionStoring, @unchecked Sendable {

    private static let storageKey = "lastPanelSessionV2"
    /// Pre-tabs key: a two-entry dictionary of paths. Still read, never written,
    /// so an upgrade resumes where the previous version left off.
    private static let legacyStorageKey = "lastPanelSession"
    private static let leftKey = "left"
    private static let rightKey = "right"

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Written as one encoded value so no part of the snapshot can be persisted
    /// out of step with the rest.
    package func save(_ snapshot: PanelSessionSnapshot) {
        guard !snapshot.leftPath.isEmpty, !snapshot.rightPath.isEmpty,
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    package func loadLastSession() -> PanelSessionSnapshot? {
        if let data = defaults.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(PanelSessionSnapshot.self, from: data),
           !snapshot.leftPath.isEmpty,
           !snapshot.rightPath.isEmpty {
            return snapshot
        }
        return loadLegacyPaths()
    }

    private func loadLegacyPaths() -> PanelSessionSnapshot? {
        guard let stored = defaults.dictionary(forKey: Self.legacyStorageKey) as? [String: String],
              let left = stored[Self.leftKey],
              let right = stored[Self.rightKey],
              !left.isEmpty,
              !right.isEmpty else {
            return nil
        }
        return PanelSessionSnapshot(leftPath: left, rightPath: right)
    }
}
