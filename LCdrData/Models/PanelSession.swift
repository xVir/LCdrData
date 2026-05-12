import Foundation

/// Identifies and seeds a single window's panels. Carried by `WindowGroup(for:)`
/// so macOS state restoration round-trips it across launches.
struct PanelSession: Hashable, Codable, Sendable {
    let id: UUID
    let leftPath: String
    let rightPath: String

    init(id: UUID = UUID(), leftPath: String, rightPath: String) {
        self.id = id
        self.leftPath = leftPath
        self.rightPath = rightPath
    }
}
