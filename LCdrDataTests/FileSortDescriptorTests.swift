//
//  FileSortDescriptorTests.swift
//  LCdrDataTests
//
//  Created by Dima Skachkov on 02.04.2026.
//

import Testing
import Foundation
@testable import LCdrData

@MainActor
struct FileSortDescriptorTests {

    @Test func defaultSortIsNameAscending() {
        // Arrange & Act
        let sort = FileSortDescriptor(column: .name, ascending: true)

        // Assert
        #expect(sort.column == .name)
        #expect(sort.ascending == true)
    }

    @Test func toggleSameColumnFlipsDirection() {
        // Arrange
        var sort = FileSortDescriptor(column: .name, ascending: true)

        // Act
        sort.toggle(column: .name)

        // Assert
        #expect(sort.column == .name)
        #expect(sort.ascending == false)
    }

    @Test func toggleDifferentColumnSwitchesToAscending() {
        // Arrange
        var sort = FileSortDescriptor(column: .name, ascending: false)

        // Act
        sort.toggle(column: .size)

        // Assert
        #expect(sort.column == .size)
        #expect(sort.ascending == true)
    }

    @Test func allColumnCasesExist() {
        // Assert
        let allCases = FileSortDescriptor.Column.allCases
        #expect(allCases.count == 5)
        #expect(allCases.contains(.name))
        #expect(allCases.contains(.size))
        #expect(allCases.contains(.dateModified))
        #expect(allCases.contains(.dateCreated))
        #expect(allCases.contains(.kind))
    }

    @Test func equatableConformance() {
        // Arrange
        let sort1 = FileSortDescriptor(column: .name, ascending: true)
        let sort2 = FileSortDescriptor(column: .name, ascending: true)
        let sort3 = FileSortDescriptor(column: .size, ascending: true)

        // Assert
        #expect(sort1 == sort2)
        #expect(sort1 != sort3)
    }
}
