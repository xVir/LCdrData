import Foundation

/// The state of one file panel, including its current directory, items, cursor, and sort.
package struct PanelState {
    package var currentDirectory: URL
    package var items: [FileItem]
    package var cursor: Cursor
    package var sortDescriptor: FileSortDescriptor
    package var showHiddenFiles: Bool

    /// Navigation history — a list of previously visited directory URLs.
    package var history: [URL]
    /// Index into the history array for the currently displayed directory.
    package var historyIndex: Int

    package init(
        currentDirectory: URL,
        items: [FileItem] = [],
        cursor: Cursor = Cursor(),
        sortDescriptor: FileSortDescriptor = FileSortDescriptor(column: .name, ascending: true),
        showHiddenFiles: Bool = false,
        history: [URL]? = nil,
        historyIndex: Int = 0
    ) {
        self.currentDirectory = currentDirectory
        self.items = items
        self.cursor = cursor
        self.sortDescriptor = sortDescriptor
        self.showHiddenFiles = showHiddenFiles
        self.history = history ?? [currentDirectory]
        self.historyIndex = historyIndex
    }
}
