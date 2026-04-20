//
//  PanelStateTests.swift
//  LCdrDataTests
//
//  Created by Dima Skachkov on 02.04.2026.
//

import Testing
import Foundation
@testable import LCdrData

@MainActor
struct PanelStateTests {

    @Test func defaultInit() {
        // Arrange & Act
        let url = URL(fileURLWithPath: "/Users/test")
        let state = PanelState(currentDirectory: url)

        // Assert
        #expect(state.currentDirectory == url)
        #expect(state.items.isEmpty)
        #expect(state.selectedItemIDs.isEmpty)
        #expect(state.focusedItemID == nil)
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
            selectedItemIDs: [item.id],
            focusedItemID: item.id,
            sortDescriptor: FileSortDescriptor(column: .size, ascending: false),
            showHiddenFiles: true
        )

        // Assert
        #expect(state.items.count == 1)
        #expect(state.selectedItemIDs.contains(item.id))
        #expect(state.focusedItemID == item.id)
        #expect(state.sortDescriptor.column == .size)
        #expect(state.sortDescriptor.ascending == false)
        #expect(state.showHiddenFiles == true)
    }
}
