import Foundation

/// The state of one file panel, including its current directory, items, cursor, and sort.
struct PanelState {
    var currentDirectory: URL
    var items: [FileItem]
    var cursor: Cursor
    var sortDescriptor: FileSortDescriptor
    var showHiddenFiles: Bool

    /// Navigation history — a list of previously visited directory URLs.
    var history: [URL]
    /// Index into the history array for the currently displayed directory.
    var historyIndex: Int

    init(
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
