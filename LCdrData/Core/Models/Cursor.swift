import Foundation

/// The user's attention in a panel listing — a focused row plus a selection set.
///
/// `focused` is the single row driving Quick Look, sort reference, and type-ahead anchor.
/// `selected` is the set of rows participating in the next file operation.
///
/// All cursor mechanics — both user-event mutations (clicks, arrow keys, type-ahead)
/// and reload-time resolution — live on this value type.
package struct Cursor: Sendable, Equatable {
    package var focused: UUID?
    package var selected: Set<UUID>

    package init(focused: UUID? = nil, selected: Set<UUID> = []) {
        self.focused = focused
        self.selected = selected
    }

    /// Caller-declared description of where the cursor should land after a reload.
    package enum Intent: Sendable, Equatable {
        /// First load, history navigation, bookmark / path-bar jumps. Lands on the first
        /// row of the new listing (the `..` row when present).
        case fresh

        /// Background refresh, sort change, hidden-files toggle, configuration apply.
        /// Preserves the previously focused row when it still exists; falls back to the
        /// same index position otherwise.
        case keepSelection

        /// After `navigateToParent()`. Lands on the directory the panel just left.
        case landOnChild(URL)

        /// After delete / move on the source side. Lands on the row adjacent to the
        /// doomed URLs in the previous listing, mapped to the new listing.
        case landOnNeighbourOf([URL])

        /// After rename / mkdir. Lands on the newly created or renamed item.
        case landOnNew(URL)
    }

    // MARK: - User-event mutations

    /// Reacts to the user mutating the selection via the list view (clicks,
    /// arrow keys, Cmd-click, range selection). An empty incoming set means the
    /// user clicked empty space — restore selection from the focused row so the
    /// cursor never disappears. A single-row selection syncs `focused` to it.
    /// Multi-row selections leave `focused` alone.
    package mutating func userDidSelect(_ newSelection: Set<UUID>) {
        if newSelection.isEmpty {
            if let focused {
                selected = [focused]
            } else {
                selected = []
            }
        } else if newSelection.count == 1 {
            selected = newSelection
            focused = newSelection.first
        } else {
            selected = newSelection
        }
    }

    /// Selects every non-parent row in the listing.
    package mutating func selectAll(in listing: [FileItem]) {
        selected = Set(listing.lazy.filter { !$0.isParentDirectory }.map(\.id))
    }

    /// Collapses the selection to the focused row. If no row is focused but the
    /// listing is non-empty, focuses (and selects) the first row.
    package mutating func deselectAllKeepingFocus(in listing: [FileItem]) {
        if let focused {
            selected = [focused]
        } else if let first = listing.first {
            focused = first.id
            selected = [first.id]
        }
    }

    /// Focuses the first non-parent row, falling back to the first row if no
    /// non-parent rows exist. Empty listings are a no-op.
    package mutating func focusFirst(in listing: [FileItem]) {
        guard let target = listing.first(where: { !$0.isParentDirectory })
                ?? listing.first else { return }
        focused = target.id
        selected = [target.id]
    }

    /// Focuses the last non-parent row, falling back to the last row if no
    /// non-parent rows exist. Empty listings are a no-op.
    package mutating func focusLast(in listing: [FileItem]) {
        guard let target = listing.last(where: { !$0.isParentDirectory })
                ?? listing.last else { return }
        focused = target.id
        selected = [target.id]
    }

    // MARK: - Reload-time resolution

    /// Computes the cursor for a freshly fetched listing.
    package static func resolve(
        intent: Intent,
        listing: [FileItem],
        previousListing: [FileItem],
        previousCursor: Cursor
    ) -> Cursor {
        guard !listing.isEmpty else { return Cursor() }
        let newIDs = Set(listing.map(\.id))

        switch intent {
        case .fresh:
            return firstRowCursor(in: listing)

        case .keepSelection:
            if let previousFocused = previousCursor.focused, newIDs.contains(previousFocused) {
                let surviving = previousCursor.selected.intersection(newIDs)
                return Cursor(
                    focused: previousFocused,
                    selected: surviving.isEmpty ? [previousFocused] : surviving
                )
            }
            let previousIndex = previousCursor.focused.flatMap { id in
                previousListing.firstIndex(where: { $0.id == id })
            } ?? 0
            let fallbackIndex = min(previousIndex, listing.count - 1)
            let fallback = listing[fallbackIndex]
            return Cursor(focused: fallback.id, selected: [fallback.id])

        case .landOnChild(let childURL):
            return cursorForRealItem(matching: childURL, in: listing)
                ?? firstRowCursor(in: listing)

        case .landOnNeighbourOf(let doomedURLs):
            if let neighbour = neighbourItem(of: doomedURLs, in: previousListing),
               let match = listing.first(where: {
                   $0.url.standardizedFileURL.path
                       == neighbour.url.standardizedFileURL.path
                       && $0.isParentDirectory == neighbour.isParentDirectory
               }) {
                return Cursor(focused: match.id, selected: [match.id])
            }
            return firstRowCursor(in: listing)

        case .landOnNew(let newURL):
            return cursorForRealItem(matching: newURL, in: listing)
                ?? firstRowCursor(in: listing)
        }
    }

    private static func firstRowCursor(in listing: [FileItem]) -> Cursor {
        let first = listing[0]
        return Cursor(focused: first.id, selected: [first.id])
    }

    private static func cursorForRealItem(
        matching url: URL,
        in listing: [FileItem]
    ) -> Cursor? {
        let standardized = url.standardizedFileURL.path
        guard let match = listing.first(where: {
            !$0.isParentDirectory
                && $0.url.standardizedFileURL.path == standardized
        }) else { return nil }
        return Cursor(focused: match.id, selected: [match.id])
    }

    /// Picks the row to focus *after* a deletion: prefer the row just after the
    /// last doomed item, fall back to the row just before the first doomed item,
    /// skipping the synthetic `..` parent row in both cases.
    private static func neighbourItem(
        of doomedURLs: [URL],
        in previousListing: [FileItem]
    ) -> FileItem? {
        let doomedPaths = Set(doomedURLs.map { $0.standardizedFileURL.path })
        let doomedIndices = previousListing.enumerated()
            .filter {
                !$0.element.isParentDirectory
                    && doomedPaths.contains($0.element.url.standardizedFileURL.path)
            }
            .map(\.offset)

        guard let lastDoomed = doomedIndices.max() else { return nil }

        let after = lastDoomed + 1
        if after < previousListing.count {
            let candidate = previousListing[after]
            if !candidate.isParentDirectory { return candidate }
        }

        guard let firstDoomed = doomedIndices.min() else { return nil }
        let before = firstDoomed - 1
        if before >= 0 {
            let candidate = previousListing[before]
            if !candidate.isParentDirectory { return candidate }
        }

        return nil
    }
}
