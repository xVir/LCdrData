import Foundation

/// The state of one file panel, including its current location, items, cursor, and sort.
package struct PanelState {
    package var location: BrowseLocation
    package var currentDirectory: URL {
        get { location.persistentDirectory }
        set { location = .directory(newValue) }
    }
    package var items: [FileItem]
    package var cursor: Cursor
    package var sortDescriptor: FileSortDescriptor
    package var showHiddenFiles: Bool

    /// Navigation history — a list of previously visited browse locations.
    package var locationHistory: [BrowseLocation]
    package var history: [URL] {
        get { locationHistory.map(\.persistentDirectory) }
        set { locationHistory = newValue.map(BrowseLocation.directory) }
    }
    /// Index into the history array for the currently displayed location.
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
        self.location = .directory(currentDirectory)
        self.items = items
        self.cursor = cursor
        self.sortDescriptor = sortDescriptor
        self.showHiddenFiles = showHiddenFiles
        self.locationHistory = (history ?? [currentDirectory]).map(BrowseLocation.directory)
        self.historyIndex = historyIndex
    }

    package init(
        location: BrowseLocation,
        items: [FileItem] = [],
        cursor: Cursor = Cursor(),
        sortDescriptor: FileSortDescriptor = FileSortDescriptor(column: .name, ascending: true),
        showHiddenFiles: Bool = false,
        history: [BrowseLocation]? = nil,
        historyIndex: Int = 0
    ) {
        self.location = location
        self.items = items
        self.cursor = cursor
        self.sortDescriptor = sortDescriptor
        self.showHiddenFiles = showHiddenFiles
        self.locationHistory = history ?? [location]
        self.historyIndex = historyIndex
    }
}
