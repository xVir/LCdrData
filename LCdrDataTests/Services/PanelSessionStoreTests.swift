import Testing
import Foundation
@testable import Models
@testable import Services
@testable import ViewModels

private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "PanelSessionStoreTests-\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

struct PanelSessionStoreTests {

    @Test func loadReturnsNilBeforeAnythingIsRecorded() {
        // Arrange
        let store = PanelSessionStore(defaults: makeIsolatedDefaults())

        // Act & Assert
        #expect(store.loadLastPaths() == nil)
    }

    @Test func savedPathsSurviveANewStoreOverTheSameDefaults() {
        // Arrange — a second store stands in for the next launch.
        let defaults = makeIsolatedDefaults()
        let store = PanelSessionStore(defaults: defaults)

        // Act
        store.save(leftPath: "/Users/dskachkov/Projects", rightPath: "/Users/dskachkov/Downloads")
        let reloaded = PanelSessionStore(defaults: defaults).loadLastPaths()

        // Assert
        #expect(reloaded?.left == "/Users/dskachkov/Projects")
        #expect(reloaded?.right == "/Users/dskachkov/Downloads")
    }

    @Test func savingAgainReplacesThePreviousPair() {
        // Arrange
        let store = PanelSessionStore(defaults: makeIsolatedDefaults())
        store.save(leftPath: "/a", rightPath: "/b")

        // Act
        store.save(leftPath: "/c", rightPath: "/d")

        // Assert
        #expect(store.loadLastPaths()?.left == "/c")
        #expect(store.loadLastPaths()?.right == "/d")
    }

    @Test func emptyPathsAreTreatedAsNothingRecorded() {
        // Arrange
        let store = PanelSessionStore(defaults: makeIsolatedDefaults())

        // Act
        store.save(leftPath: "", rightPath: "/b")

        // Assert
        #expect(store.loadLastPaths() == nil)
    }

    @Test func panelSessionRoundTripsTabCollectionsAndActiveIndexes() throws {
        // Arrange
        let session = PanelSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555666666")!,
            leftPath: "/tmp/left",
            rightPath: "/tmp/right",
            leftTabPaths: ["/tmp/left", "/tmp/left/other"],
            rightTabPaths: ["/tmp/right"],
            leftActiveTabIndex: 1,
            rightActiveTabIndex: 0
        )

        // Act
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(PanelSession.self, from: data)

        // Assert
        #expect(decoded.leftTabPaths == ["/tmp/left", "/tmp/left/other"])
        #expect(decoded.rightTabPaths == ["/tmp/right"])
        #expect(decoded.leftActiveTabIndex == 1)
        #expect(decoded.rightActiveTabIndex == 0)
    }

    @Test func restoringTabsIgnoresInvalidPathsAndFallsBackToLastValidLocation() {
        // Arrange
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp/valid")
        )

        // Act
        vm.restoreTabs(
            from: ["/definitely/not/here", "/tmp/valid"],
            fallbackDirectory: URL(fileURLWithPath: "/tmp/valid"),
            activeIndex: 1
        )

        // Assert
        #expect(vm.state.tabs.count == 1)
        #expect(vm.state.activeTabIndex == 0)
        #expect(vm.state.location == .directory(URL(fileURLWithPath: "/tmp/valid")))
    }

    @Test func creatingTabFromContextMenuUsesTheTargetTabAsSource() async {
        // Arrange
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp/active")
        )
        vm.state.tabs = [
            PanelTab(
                location: .directory(URL(fileURLWithPath: "/tmp/active")),
                title: "active",
                sortDescriptor: FileSortDescriptor(column: .name, ascending: true),
                showHiddenFiles: true
            ),
            PanelTab(
                location: .directory(URL(fileURLWithPath: "/tmp/target")),
                title: "target",
                sortDescriptor: FileSortDescriptor(column: .size, ascending: false),
                showHiddenFiles: false
            )
        ]
        vm.state.activeTabIndex = 0

        // Act
        await vm.createTab(from: 1)

        // Assert
        #expect(vm.state.tabs.count == 3)
        #expect(vm.state.activeTabIndex == 2)
        #expect(vm.state.activeTab?.location == .directory(URL(fileURLWithPath: "/tmp/target")))
        #expect(vm.state.activeTab?.showHiddenFiles == false)
        #expect(vm.state.activeTab?.sortDescriptor == FileSortDescriptor(column: .size, ascending: false))
    }

    @Test func tabPathForContextMenuUsesTheRequestedTabIndex() {
        // Arrange
        let vm = PanelViewModel(
            side: .left,
            initialDirectory: URL(fileURLWithPath: "/tmp/active")
        )
        vm.state.tabs = [
            PanelTab(location: .directory(URL(fileURLWithPath: "/tmp/active"))),
            PanelTab(location: .directory(URL(fileURLWithPath: "/tmp/target")))
        ]
        vm.state.activeTabIndex = 0

        // Act
        let path = vm.tabPath(at: 1)

        // Assert
        #expect(path == "/tmp/target")
    }
}
