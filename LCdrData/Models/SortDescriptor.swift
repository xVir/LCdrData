import Foundation

/// Describes how a file panel's items are sorted.
struct FileSortDescriptor: Equatable, Sendable {
    enum Column: String, CaseIterable {
        case name
        case size
        case dateModified
        case dateCreated
        case kind
    }

    var column: Column
    var ascending: Bool

    /// Toggles the sort direction, or switches to a new column (defaulting to ascending).
    mutating func toggle(column newColumn: Column) {
        if column == newColumn {
            ascending.toggle()
        } else {
            column = newColumn
            ascending = true
        }
    }
}
