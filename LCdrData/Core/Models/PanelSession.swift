import Foundation

/// Identifies and seeds a single window's panels. Carried by `WindowGroup(for:)`
/// so macOS state restoration round-trips it across launches.
package struct PanelSession: Hashable, Codable, Sendable {
    package let id: UUID
    package let leftPath: String
    package let rightPath: String

    package init(id: UUID = UUID(), leftPath: String, rightPath: String) {
        self.id = id
        self.leftPath = leftPath
        self.rightPath = rightPath
    }
}
