import Foundation

/// A panel-local browsing context, equivalent to a macOS tab.
package struct PanelTab: Identifiable, Hashable, Sendable {
    package let id: UUID
    package var location: BrowseLocation
    package var title: String
    package var viewMode: String
    package var cursor: Cursor
    package var sortDescriptor: FileSortDescriptor
    package var showHiddenFiles: Bool
    package var scrollOffset: Double?
    package var columns: [String]
    package var items: [FileItem]?

    package var currentDirectory: URL {
        get { location.persistentDirectory }
        set { location = .directory(newValue) }
    }

    package var cachedListing: [FileItem]? {
        get { items }
        set { items = newValue }
    }

    package var selectionState: Cursor {
        get { cursor }
        set { cursor = newValue }
    }

    package init(
        id: UUID = UUID(),
        location: BrowseLocation,
        title: String? = nil,
        viewMode: String = "list",
        cursor: Cursor = Cursor(),
        sortDescriptor: FileSortDescriptor = FileSortDescriptor(column: .name, ascending: true),
        showHiddenFiles: Bool = false,
        scrollOffset: Double? = nil,
        columns: [String] = [],
        items: [FileItem]? = nil
    ) {
        self.id = id
        self.location = location
        self.title = title ?? location.persistentDirectory.lastPathComponent
        self.viewMode = viewMode
        self.cursor = cursor
        self.sortDescriptor = sortDescriptor
        self.showHiddenFiles = showHiddenFiles
        self.scrollOffset = scrollOffset
        self.columns = columns
        self.items = items
    }
}

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

    package var tabs: [PanelTab]
    package var activeTabIndex: Int
    package var activeTab: PanelTab? {
        guard tabs.indices.contains(activeTabIndex) else { return nil }
        return tabs[activeTabIndex]
    }
    package var isTabBarVisible: Bool { tabs.count > 1 }

    private static func clampTabIndex(_ index: Int, tabCount: Int) -> Int {
        guard tabCount > 0 else { return 0 }
        return min(max(index, 0), tabCount - 1)
    }

    private mutating func syncLocationAndAppearanceFromActiveTab() {
        guard let active = activeTab else {
            if tabs.isEmpty {
                tabs = [PanelTab(location: location)]
            }
            return
        }

        location = active.location
        cursor = active.cursor
        sortDescriptor = active.sortDescriptor
        showHiddenFiles = active.showHiddenFiles
        if let cached = active.items {
            items = cached
        }
    }

    package mutating func activateTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = Self.clampTabIndex(index, tabCount: tabs.count)
        syncLocationAndAppearanceFromActiveTab()
    }

    package mutating func appendTab(
        at index: Int = -1,
        location: BrowseLocation,
        title: String? = nil,
        viewMode: String = "list",
        cursor: Cursor? = nil,
        sortDescriptor: FileSortDescriptor? = nil,
        showHiddenFiles: Bool? = nil,
        scrollOffset: Double? = nil,
        columns: [String] = [],
        items: [FileItem]? = nil
    ) {
        let insertionIndex = index == -1 ? activeTabIndex + 1 : index
        let safeIndex = max(0, min(insertionIndex, tabs.count))
        let tab = PanelTab(
            location: location,
            title: title,
            viewMode: viewMode,
            cursor: cursor ?? self.cursor,
            sortDescriptor: sortDescriptor ?? self.sortDescriptor,
            showHiddenFiles: showHiddenFiles ?? self.showHiddenFiles,
            scrollOffset: scrollOffset,
            columns: columns,
            items: items ?? self.items
        )

        tabs.insert(tab, at: safeIndex)
        activeTabIndex = Self.clampTabIndex(safeIndex, tabCount: tabs.count)
        syncLocationAndAppearanceFromActiveTab()
    }

    package mutating func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        let safeIndex = Self.clampTabIndex(index, tabCount: tabs.count)
        let wasActive = safeIndex == activeTabIndex
        tabs.remove(at: safeIndex)

        if wasActive {
            activeTabIndex = safeIndex < tabs.count ? safeIndex : max(0, tabs.count - 1)
        } else if safeIndex < activeTabIndex {
            activeTabIndex -= 1
        }

        activeTabIndex = Self.clampTabIndex(activeTabIndex, tabCount: tabs.count)
        if !tabs.isEmpty {
            syncLocationAndAppearanceFromActiveTab()
        }
    }

    package mutating func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source) else { return }
        let safeSource = Self.clampTabIndex(source, tabCount: tabs.count)
        let safeDestination = Self.clampTabIndex(destination, tabCount: tabs.count)
        let tab = tabs.remove(at: safeSource)
        tabs.insert(tab, at: safeDestination)

        if activeTabIndex == safeSource {
            activeTabIndex = safeDestination
        } else if safeSource < activeTabIndex && safeDestination >= activeTabIndex {
            activeTabIndex -= 1
        } else if safeSource > activeTabIndex && safeDestination <= activeTabIndex {
            activeTabIndex += 1
        }

        activeTabIndex = Self.clampTabIndex(activeTabIndex, tabCount: tabs.count)
        syncLocationAndAppearanceFromActiveTab()
    }

    package init(
        currentDirectory: URL,
        items: [FileItem] = [],
        cursor: Cursor = Cursor(),
        sortDescriptor: FileSortDescriptor = FileSortDescriptor(column: .name, ascending: true),
        showHiddenFiles: Bool = false,
        history: [URL]? = nil,
        historyIndex: Int = 0,
        tabs: [PanelTab]? = nil,
        activeTabIndex: Int = 0
    ) {
        let defaultLocation = BrowseLocation.directory(currentDirectory)
        let defaultTab = PanelTab(
            location: defaultLocation,
            title: currentDirectory.lastPathComponent,
            cursor: cursor,
            sortDescriptor: sortDescriptor,
            showHiddenFiles: showHiddenFiles,
            items: items
        )

        self.location = defaultLocation
        self.items = items
        self.cursor = cursor
        self.sortDescriptor = sortDescriptor
        self.showHiddenFiles = showHiddenFiles
        self.locationHistory = (history ?? [currentDirectory]).map(BrowseLocation.directory)
        self.historyIndex = historyIndex
        self.tabs = tabs ?? [defaultTab]
        if self.tabs.isEmpty {
            self.tabs = [defaultTab]
        }
        self.activeTabIndex = Self.clampTabIndex(activeTabIndex, tabCount: self.tabs.count)
        syncLocationAndAppearanceFromActiveTab()
    }

    package init(
        location: BrowseLocation,
        items: [FileItem] = [],
        cursor: Cursor = Cursor(),
        sortDescriptor: FileSortDescriptor = FileSortDescriptor(column: .name, ascending: true),
        showHiddenFiles: Bool = false,
        history: [BrowseLocation]? = nil,
        historyIndex: Int = 0,
        tabs: [PanelTab]? = nil,
        activeTabIndex: Int = 0
    ) {
        let defaultTab = PanelTab(
            location: location,
            title: location.persistentDirectory.lastPathComponent,
            cursor: cursor,
            sortDescriptor: sortDescriptor,
            showHiddenFiles: showHiddenFiles,
            items: items
        )

        self.location = location
        self.items = items
        self.cursor = cursor
        self.sortDescriptor = sortDescriptor
        self.showHiddenFiles = showHiddenFiles
        self.locationHistory = history ?? [location]
        self.historyIndex = historyIndex
        self.tabs = tabs ?? [defaultTab]
        if self.tabs.isEmpty {
            self.tabs = [defaultTab]
        }
        self.activeTabIndex = Self.clampTabIndex(activeTabIndex, tabCount: self.tabs.count)
        syncLocationAndAppearanceFromActiveTab()
    }
}
