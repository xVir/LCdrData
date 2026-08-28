import Foundation

/// A column the file table can draw. Deliberately narrower than
/// `FileSortDescriptor.Column`, which also has `dateCreated` — sortable in
/// principle, but with no column of its own today.
package nonisolated enum FileColumn: String, CaseIterable, Sendable {
    case name
    case size
    case dateModified
    case kind

    /// Below this a column stops being readable, so no drag may take it further.
    package nonisolated var minimumWidth: Double {
        switch self {
        case .name: 120
        case .size: 48
        case .dateModified: 80
        case .kind: 48
        }
    }
}

/// The order of a panel's columns and the width of each fixed-width one.
///
/// `name` carries no stored width: it is the slack column and always absorbs
/// whatever the panel's width leaves over, so the resolved widths add up to
/// exactly the space available.
package nonisolated struct PanelColumnLayout: Equatable, Sendable, Codable {

    package nonisolated struct Entry: Equatable, Sendable {
        package var column: FileColumn
        /// Ignored for `.name`, which is sized by what the others leave behind.
        package var width: Double

        package nonisolated init(column: FileColumn, width: Double) {
            self.column = column
            self.width = width
        }
    }

    package private(set) var entries: [Entry]

    package var columns: [FileColumn] { entries.map(\.column) }

    /// Matches the widths the file table used before columns became adjustable,
    /// so the first launch after upgrading looks like the launch before it.
    package nonisolated static let defaults = PanelColumnLayout(entries: [
        Entry(column: .name, width: 0),
        Entry(column: .size, width: 80),
        Entry(column: .dateModified, width: 140),
        Entry(column: .kind, width: 80)
    ])

    private nonisolated init(entries: [Entry]) {
        self.entries = entries
    }

    /// Builds a layout from data that came from outside the app — persisted by
    /// an older or newer version, or edited by hand. Anything unrecognised is
    /// dropped and anything missing is appended, so no input can produce a
    /// layout the table cannot draw.
    package nonisolated init(sanitizing raw: [Entry]) {
        var seen: Set<FileColumn> = []
        var kept: [Entry] = []
        for entry in raw where seen.insert(entry.column).inserted {
            // `name` is sized by subtraction, so it is normalised to zero
            // rather than clamped — a stored width for it means nothing, and
            // leaving one in place would make two equal layouts compare unequal.
            kept.append(Entry(
                column: entry.column,
                width: entry.column == .name ? 0 : max(entry.column.minimumWidth, entry.width)
            ))
        }
        for column in FileColumn.allCases where !seen.contains(column) {
            kept.append(Entry(column: column, width: Self.defaultWidth(for: column)))
        }
        self.entries = kept
    }

    private nonisolated static func defaultWidth(for column: FileColumn) -> Double {
        defaults.entries.first { $0.column == column }?.width ?? column.minimumWidth
    }

    // MARK: - Codable

    /// The persisted form. Columns are stored as raw strings rather than as the
    /// enum so that a name this version does not know — written by a later one,
    /// or retired by it — is skipped on its own instead of taking the whole
    /// layout down with it.
    private nonisolated struct Wire: Codable {
        var column: String
        var width: Double
    }

    package nonisolated init(from decoder: Decoder) throws {
        let wire = try decoder.singleValueContainer().decode([Wire].self)
        self.init(sanitizing: wire.compactMap { stored in
            FileColumn(rawValue: stored.column).map { Entry(column: $0, width: stored.width) }
        })
    }

    package nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries.map { Wire(column: $0.column.rawValue, width: $0.width) })
    }

    /// The widths to draw, in display order. They add up to `availableWidth`,
    /// the slack landing on `name`.
    package nonisolated func resolvedWidths(availableWidth: Double) -> [Double] {
        let fixedTotal = entries
            .filter { $0.column != .name }
            .reduce(0) { $0 + $1.width }
        let nameWidth = max(FileColumn.name.minimumWidth, availableWidth - fixedTotal)
        return entries.map { $0.column == .name ? nameWidth : $0.width }
    }

    /// Applies a divider drag. `index` addresses the column to the left of the
    /// divider, so it is always in `0..<entries.count - 1`.
    ///
    /// The divider itself has to end up under the pointer, which is the whole
    /// point of grabbing it: the column on its left takes the movement and the
    /// column on its right gives the same amount back, so every divider except
    /// the one being dragged stays exactly where it was. Charging the whole
    /// change to `name` instead — as this did — pins the dragged divider in
    /// place and moves a different one, because `name` is the slack column and
    /// sits to the left of the rest.
    ///
    /// `name` has no width of its own, so when it is on either side of the
    /// divider the opposite column carries the whole change and `name` follows
    /// by subtraction.
    package nonisolated func resizing(
        dividerAfter index: Int,
        by delta: Double,
        availableWidth: Double
    ) -> PanelColumnLayout {
        let next = index + 1
        guard entries.indices.contains(index), entries.indices.contains(next) else { return self }

        let left = entries[index]
        let right = entries[next]
        var updated = entries

        if left.column == .name {
            // Widening `name` means narrowing the column to its right.
            updated[next].width = clamped(
                right.width - delta,
                for: right.column,
                replacing: right.column,
                availableWidth: availableWidth
            )
        } else if right.column == .name {
            updated[index].width = clamped(
                left.width + delta,
                for: left.column,
                replacing: left.column,
                availableWidth: availableWidth
            )
        } else {
            // Neither side is derived, so the pair trades width between
            // themselves and `name` is untouched. The move is limited by
            // whichever of the two reaches its minimum first.
            let applied = min(
                max(delta, -(left.width - left.column.minimumWidth)),
                right.width - right.column.minimumWidth
            )
            updated[index].width = left.width + applied
            updated[next].width = right.width - applied
        }
        return PanelColumnLayout(entries: updated)
    }

    /// Holds a fixed column's width to its own minimum and to whatever leaves
    /// `name` its minimum — a drag can only ever spend the slack that this
    /// panel's width actually has.
    private nonisolated func clamped(
        _ width: Double,
        for column: FileColumn,
        replacing replaced: FileColumn,
        availableWidth: Double
    ) -> Double {
        let otherFixedTotal = entries
            .filter { $0.column != .name && $0.column != replaced }
            .reduce(0) { $0 + $1.width }
        let ceiling = availableWidth - otherFixedTotal - FileColumn.name.minimumWidth
        return min(max(column.minimumWidth, width), max(column.minimumWidth, ceiling))
    }

    /// Where a header dragged `translationX` from its resting place should
    /// land: the moving column's centre is compared against the centres of the
    /// columns it passes over, so a column swaps only once it is more than
    /// halfway across its neighbour.
    package nonisolated func targetIndex(
        draggedIndex: Int,
        translationX: Double,
        widths: [Double]
    ) -> Int {
        guard widths.indices.contains(draggedIndex) else { return draggedIndex }

        var leadingEdges: [Double] = []
        var running: Double = 0
        for width in widths {
            leadingEdges.append(running)
            running += width
        }
        let draggedCentre = leadingEdges[draggedIndex] + widths[draggedIndex] / 2 + translationX

        var target = draggedIndex
        for index in widths.indices where index != draggedIndex {
            let centre = leadingEdges[index] + widths[index] / 2
            if index < draggedIndex, draggedCentre < centre {
                target = min(target, index)
            } else if index > draggedIndex, draggedCentre > centre {
                target = max(target, index)
            }
        }
        return target
    }

    /// Moves the column at `from` so it comes to rest at display index `to`,
    /// keeping its width. Out-of-range indices leave the layout untouched.
    package nonisolated func moving(from: Int, to: Int) -> PanelColumnLayout {
        guard entries.indices.contains(from), entries.indices.contains(to), from != to else {
            return self
        }
        var updated = entries
        let entry = updated.remove(at: from)
        updated.insert(entry, at: to)
        return PanelColumnLayout(entries: updated)
    }
}
