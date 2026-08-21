import Foundation

/// Describes how a file panel's items are sorted.
package struct FileSortDescriptor: Equatable, Sendable {
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
