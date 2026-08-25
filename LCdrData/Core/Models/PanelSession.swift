import Foundation

/// Identifies and seeds a single window's panels. Carried by `WindowGroup(for:)`
/// so macOS state restoration round-trips it across launches.
package struct PanelSession: Hashable, Codable, Sendable {
    package let id: UUID
    package let leftPath: String
    package let rightPath: String
    /// In-memory locations used when cloning a live window. They are
    /// deliberately excluded from Codable state restoration.
    package let leftLocation: BrowseLocation?
    package let rightLocation: BrowseLocation?

    package init(
        id: UUID = UUID(),
        leftPath: String,
        rightPath: String,
        leftLocation: BrowseLocation? = nil,
        rightLocation: BrowseLocation? = nil
    ) {
        self.id = id
        self.leftPath = leftPath
        self.rightPath = rightPath
        self.leftLocation = leftLocation
        self.rightLocation = rightLocation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case leftPath
        case rightPath
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.leftPath = try container.decode(String.self, forKey: .leftPath)
        self.rightPath = try container.decode(String.self, forKey: .rightPath)
        self.leftLocation = nil
        self.rightLocation = nil
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(leftPath, forKey: .leftPath)
        try container.encode(rightPath, forKey: .rightPath)
    }
}
