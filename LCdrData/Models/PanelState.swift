//
//  PanelState.swift
//  LCdrData
//
//  Created by Dima Skachkov on 02.04.2026.
//

import Foundation

/// The state of one file panel, including its current directory, items, selection, and sort.
struct PanelState {
    var currentDirectory: URL
    var items: [FileItem]
    var selectedItemIDs: Set<UUID>
    var focusedItemID: UUID?
    var sortDescriptor: FileSortDescriptor
    var showHiddenFiles: Bool

    /// Navigation history — a list of previously visited directory URLs.
    var history: [URL]
    /// Index into the history array for the currently displayed directory.
    var historyIndex: Int

    init(
        currentDirectory: URL,
        items: [FileItem] = [],
        selectedItemIDs: Set<UUID> = [],
        focusedItemID: UUID? = nil,
        sortDescriptor: FileSortDescriptor = FileSortDescriptor(column: .name, ascending: true),
        showHiddenFiles: Bool = false,
        history: [URL]? = nil,
        historyIndex: Int = 0
    ) {
        self.currentDirectory = currentDirectory
        self.items = items
        self.selectedItemIDs = selectedItemIDs
        self.focusedItemID = focusedItemID
        self.sortDescriptor = sortDescriptor
        self.showHiddenFiles = showHiddenFiles
        self.history = history ?? [currentDirectory]
        self.historyIndex = historyIndex
    }
}
