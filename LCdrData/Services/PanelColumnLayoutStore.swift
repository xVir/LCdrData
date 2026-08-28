import Foundation
import Models

/// Remembers each panel's column order and widths.
///
/// This lives in `UserDefaults` rather than the KDL configuration file on
/// purpose: the KDL file is hand-edited, and dragging a column divider must not
/// rewrite it underneath the user.
package protocol PanelColumnLayoutStoring: Sendable {
    func save(left: PanelColumnLayout, right: PanelColumnLayout)
    /// The layouts last recorded, or `nil` before anything has been recorded or
    /// when what was recorded can no longer be read.
    func load() -> (left: PanelColumnLayout, right: PanelColumnLayout)?
}

package final class PanelColumnLayoutStore: PanelColumnLayoutStoring, @unchecked Sendable {

    private static let storageKey = "panelColumnLayouts"

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Written as a single payload so the two panels can never be persisted out
    /// of step with one another.
    package func save(left: PanelColumnLayout, right: PanelColumnLayout) {
        guard let data = try? JSONEncoder().encode(StoredPair(left: left, right: right)) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    package func load() -> (left: PanelColumnLayout, right: PanelColumnLayout)? {
        guard let data = defaults.data(forKey: Self.storageKey),
              let pair = try? JSONDecoder().decode(StoredPair.self, from: data) else {
            return nil
        }
        return (pair.left, pair.right)
    }
}

private nonisolated struct StoredPair: Codable {
    var left: PanelColumnLayout
    var right: PanelColumnLayout
}
