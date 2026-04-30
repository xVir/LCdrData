import Foundation

/// Effective application settings merged from bundled defaults and user KDL overrides.
struct AppConfiguration: Equatable, Sendable {

    struct BookmarkEntry: Equatable, Sendable {
        var label: String
        var path: String
    }

    var panelShowHiddenFiles: Bool
    var panelSortColumn: FileSortDescriptor.Column
    var panelSortAscending: Bool
    var appearanceFontSize: Double
    var appearanceDateFormat: String
    var bookmarkEntries: [BookmarkEntry]
    var editorDefaultAppBundleID: String?

    static let defaults = AppConfiguration(
        panelShowHiddenFiles: false,
        panelSortColumn: .name,
        panelSortAscending: true,
        appearanceFontSize: 13,
        appearanceDateFormat: "yyyy-MM-dd HH:mm",
        bookmarkEntries: [
            BookmarkEntry(label: "Projects", path: "~/Projects"),
            BookmarkEntry(label: "Downloads", path: "~/Downloads")
        ],
        editorDefaultAppBundleID: "com.apple.TextEdit"
    )

    var sortDescriptor: FileSortDescriptor {
        FileSortDescriptor(column: panelSortColumn, ascending: panelSortAscending)
    }
}
