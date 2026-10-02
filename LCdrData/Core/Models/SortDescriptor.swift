import Foundation

/// Describes how a file panel's items are sorted.
package struct FileSortDescriptor: Equatable, Hashable, Sendable, Codable {
    package enum Column: String, CaseIterable {
        case name
        case size
        case dateModified
        case dateCreated
        case kind
    }

    package var column: Column
    package var ascending: Bool

    package init(column: Column, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }

    private enum CodingKeys: String, CodingKey {
        case column
        case ascending
    }

    /// A column name this version does not know becomes name order, so one
    /// unfamiliar value cannot discard the rest of a saved session.
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawColumn = try container.decode(String.self, forKey: .column)
        self.column = Column(rawValue: rawColumn) ?? .name
        self.ascending = try container.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(column.rawValue, forKey: .column)
        try container.encode(ascending, forKey: .ascending)
    }

    /// Toggles the sort direction, or switches to a new column (defaulting to ascending).
    package mutating func toggle(column newColumn: Column) {
        if column == newColumn {
            ascending.toggle()
        } else {
            column = newColumn
            ascending = true
        }
    }
}
