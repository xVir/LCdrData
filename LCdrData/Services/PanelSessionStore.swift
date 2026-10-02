import Foundation
import Models

/// A window's panels as they should come back on the next launch: the two
/// directories, the tabs open in each panel, each tab's column sort, and which
/// tab was in front.
package struct PanelSessionSnapshot: Codable, Equatable, Sendable {
    package let leftPath: String
    package let rightPath: String
    package let leftTabPaths: [String]
    package let rightTabPaths: [String]
    /// Aligned with `leftTabPaths`. Empty when the snapshot predates per-tab sort.
    package let leftTabSorts: [FileSortDescriptor]
    /// Aligned with `rightTabPaths`. Empty when the snapshot predates per-tab sort.
    package let rightTabSorts: [FileSortDescriptor]
    package let leftActiveTabIndex: Int
    package let rightActiveTabIndex: Int

    package init(
        leftPath: String,
        rightPath: String,
        leftTabPaths: [String] = [],
        rightTabPaths: [String] = [],
        leftTabSorts: [FileSortDescriptor] = [],
        rightTabSorts: [FileSortDescriptor] = [],
        leftActiveTabIndex: Int = 0,
        rightActiveTabIndex: Int = 0
    ) {
        self.leftPath = leftPath
        self.rightPath = rightPath
        // A snapshot always describes at least the panel's own directory, so a
        // reader never has to decide what an empty tab list means.
        self.leftTabPaths = leftTabPaths.isEmpty ? [leftPath] : leftTabPaths
        self.rightTabPaths = rightTabPaths.isEmpty ? [rightPath] : rightTabPaths
        self.leftTabSorts = leftTabSorts
        self.rightTabSorts = rightTabSorts
        self.leftActiveTabIndex = max(0, leftActiveTabIndex)
        self.rightActiveTabIndex = max(0, rightActiveTabIndex)
    }

    private enum CodingKeys: String, CodingKey {
        case leftPath
        case rightPath
        case leftTabPaths
        case rightTabPaths
        case leftTabSorts
        case rightTabSorts
        case leftActiveTabIndex
        case rightActiveTabIndex
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            leftPath: container.decode(String.self, forKey: .leftPath),
            rightPath: container.decode(String.self, forKey: .rightPath),
            leftTabPaths: container.decodeIfPresent([String].self, forKey: .leftTabPaths) ?? [],
            rightTabPaths: container.decodeIfPresent([String].self, forKey: .rightTabPaths) ?? [],
            leftTabSorts: container.decodeIfPresent([FileSortDescriptor].self, forKey: .leftTabSorts) ?? [],
            rightTabSorts: container.decodeIfPresent([FileSortDescriptor].self, forKey: .rightTabSorts) ?? [],
            leftActiveTabIndex: container.decodeIfPresent(Int.self, forKey: .leftActiveTabIndex) ?? 0,
            rightActiveTabIndex: container.decodeIfPresent(Int.self, forKey: .rightActiveTabIndex) ?? 0
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(leftPath, forKey: .leftPath)
        try container.encode(rightPath, forKey: .rightPath)
        try container.encode(leftTabPaths, forKey: .leftTabPaths)
        try container.encode(rightTabPaths, forKey: .rightTabPaths)
        try container.encode(leftTabSorts, forKey: .leftTabSorts)
        try container.encode(rightTabSorts, forKey: .rightTabSorts)
        try container.encode(leftActiveTabIndex, forKey: .leftActiveTabIndex)
        try container.encode(rightActiveTabIndex, forKey: .rightActiveTabIndex)
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
