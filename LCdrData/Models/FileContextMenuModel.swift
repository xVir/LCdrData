import Foundation

/// The pure, testable decision layer behind a panel's **context menu**.
///
/// Given a raw selection set and the current listing, it resolves which
/// **variant** of the menu to present and the real (non-`..`) items the menu
/// should act on. Kept free of SwiftUI so the branching logic can be unit
/// tested independently of the view.
struct FileContextMenuModel: Equatable {

    /// Which flavour of context menu a secondary click resolves to.
    enum Variant: Equatable {
        /// One or more real (non-`..`) rows are selected.
        case selection
        /// The click resolved to only the synthetic `..` parent row.
        case parent
        /// Empty selection — a secondary click on blank space below the rows.
        case background
    }

    let variant: Variant

    /// The real, non-parent items the menu acts on. Empty for `.parent` and
    /// `.background`. Preserves listing order.
    let items: [FileItem]

    /// True when exactly one real item is selected.
    var isSingleSelection: Bool { items.count == 1 }

    /// Rename applies only to a single real item.
    var canRename: Bool { isSingleSelection }

    /// The single item when exactly one real item is selected, else `nil`.
    var singleItem: FileItem? { isSingleSelection ? items.first : nil }

    /// File URLs of the resolved items, in listing order.
    var urls: [URL] { items.map(\.url) }

    /// Resolves the menu variant and acted-on items from a raw selection set
    /// against the current listing.
    ///
    /// - A set containing at least one real item -> `.selection` (parent rows,
    ///   if any, are filtered out of `items`).
    /// - A set that resolves to only the `..` row -> `.parent`.
    /// - An empty (or fully unresolved) set -> `.background`.
    static func resolve(selection: Set<UUID>, in listing: [FileItem]) -> FileContextMenuModel {
        let selectedItems = listing.filter { selection.contains($0.id) }
        let realItems = selectedItems.filter { !$0.isParentDirectory }

        if !realItems.isEmpty {
            return FileContextMenuModel(variant: .selection, items: realItems)
        }

        if selectedItems.contains(where: { $0.isParentDirectory }) {
            return FileContextMenuModel(variant: .parent, items: [])
        }

        return FileContextMenuModel(variant: .background, items: [])
    }
}
