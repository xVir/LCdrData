import Foundation

/// Effective application settings merged from bundled defaults and user KDL overrides.
package struct AppConfiguration: Equatable, Sendable {

    package struct BookmarkEntry: Equatable, Sendable {
        package var label: String
        package var path: String

        package init(label: String, path: String) {
            self.label = label
            self.path = path
        }
    }

    package var panelShowHiddenFiles: Bool
    package var panelSortColumn: FileSortDescriptor.Column
    package var panelSortAscending: Bool
    package var appearanceFontSize: Double
    package var appearanceDateFormat: String
    package var bookmarkEntries: [BookmarkEntry]
    package var editorDefaultAppBundleID: String?
    package var editorOpenFolders: Bool
    /// Bundle identifier of the application "Open in Terminal" uses.
    /// `terminal.default-app` in KDL. macOS Terminal by default.
    package var terminalDefaultAppBundleID: String
    /// How many background file operations may run at once in one window.
    /// Further ones stay waiting until a slot frees. `operations.max-active` in KDL.
    package var operationsMaxActive: Int

    package static let defaults = AppConfiguration(
        panelShowHiddenFiles: false,
        panelSortColumn: .name,
        panelSortAscending: true,
        appearanceFontSize: 13,
        appearanceDateFormat: "yyyy-MM-dd HH:mm",
        bookmarkEntries: [
            BookmarkEntry(label: "Projects", path: "~/Projects"),
            BookmarkEntry(label: "Downloads", path: "~/Downloads")
        ],
        editorDefaultAppBundleID: "com.apple.TextEdit",
        editorOpenFolders: false,
        terminalDefaultAppBundleID: TerminalApplications.macOSTerminalBundleID,
        operationsMaxActive: 3
    )

    package var sortDescriptor: FileSortDescriptor {
        FileSortDescriptor(column: panelSortColumn, ascending: panelSortAscending)
    }
}
