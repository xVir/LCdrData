import Testing
import Foundation
@testable import Models

@MainActor
struct PanelStateTests {

    @Test func defaultInit() {
        // Arrange & Act
        let url = URL(fileURLWithPath: "/Users/test")
        let state = PanelState(currentDirectory: url)

        // Assert
        #expect(state.currentDirectory == url)
        #expect(state.items.isEmpty)
        #expect(state.cursor.selected.isEmpty)
        #expect(state.cursor.focused == nil)
        #expect(state.sortDescriptor == FileSortDescriptor(column: .name, ascending: true))
        #expect(state.showHiddenFiles == false)
        #expect(state.history == [url])
        #expect(state.historyIndex == 0)
    }

    @Test func customInit() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp")
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/file"),
            name: "file",
            isDirectory: false
        )

        // Act
        let state = PanelState(
            currentDirectory: url,
            items: [item],
            cursor: Cursor(focused: item.id, selected: [item.id]),
            sortDescriptor: FileSortDescriptor(column: .size, ascending: false),
            showHiddenFiles: true
        )

        // Assert
        #expect(state.items.count == 1)
        #expect(state.cursor.selected.contains(item.id))
        #expect(state.cursor.focused == item.id)
        #expect(state.sortDescriptor.column == .size)
        #expect(state.sortDescriptor.ascending == false)
        #expect(state.showHiddenFiles == true)
    }

    @Test func initialDirectoryBecomesBrowseLocationAndHistoryEntry() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp")

        // Act
        let state = PanelState(currentDirectory: url)

        // Assert
        #expect(state.location == .directory(url))
        #expect(state.locationHistory == [.directory(url)])
    }

    @Test func defaultStateCreatesSingleActiveTab() {
        // Arrange
        let url = URL(fileURLWithPath: "/tmp")

        // Act
        let state = PanelState(currentDirectory: url)

        // Assert
        #expect(state.tabs.count == 1)
        #expect(state.activeTabIndex == 0)
        #expect(state.activeTab?.location == .directory(url))
        #expect(state.isTabBarVisible == false)
    }

    @Test func appendingTabsKeepsActiveTabAndTabBarVisible() {
        // Arrange
        var state = PanelState(currentDirectory: URL(fileURLWithPath: "/tmp/left"))

        // Act
        state.appendTab(at: 1, location: .directory(URL(fileURLWithPath: "/tmp/right")))

        // Assert
        #expect(state.tabs.count == 2)
        #expect(state.activeTabIndex == 1)
        #expect(state.activeTab?.location == .directory(URL(fileURLWithPath: "/tmp/right")))
        #expect(state.isTabBarVisible == true)
    }

    @Test func closingActiveTabChoosesNearestSurvivingTab() {
        // Arrange
        var state = PanelState(currentDirectory: URL(fileURLWithPath: "/tmp/first"))
        state.appendTab(at: 1, location: .directory(URL(fileURLWithPath: "/tmp/second")))
        state.appendTab(at: 2, location: .directory(URL(fileURLWithPath: "/tmp/third")))
        state.activateTab(at: 2)

        // Act
        state.closeTab(at: 2)

        // Assert
        #expect(state.tabs.count == 2)
        #expect(state.activeTabIndex == 1)
        #expect(state.activeTab?.location == .directory(URL(fileURLWithPath: "/tmp/second")))
    }
}
