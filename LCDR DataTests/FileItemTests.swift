//
//  FileItemTests.swift
//  LCDR DataTests
//
//  Created by Dima Skachkov on 02.04.2026.
//

import Testing
import Foundation
@testable import LCDR_Data

@MainActor
struct FileItemTests {

    @Test func initSetsAllProperties() {
        // Arrange
        let url = URL(fileURLWithPath: "/Users/test/file.txt")
        let date = Date()

        // Act
        let item = FileItem(
            url: url,
            name: "file.txt",
            isDirectory: false,
            size: 1024,
            modificationDate: date,
            creationDate: date,
            isHidden: false,
            isSymlink: false,
            permissions: 0o644
        )

        // Assert
        #expect(item.name == "file.txt")
        #expect(item.isDirectory == false)
        #expect(item.size == 1024)
        #expect(item.modificationDate == date)
        #expect(item.creationDate == date)
        #expect(item.isHidden == false)
        #expect(item.isSymlink == false)
        #expect(item.permissions == 0o644)
        #expect(item.isParentDirectory == false)
        #expect(item.url == url)
    }

    @Test func parentEntrySetsCorrectProperties() {
        // Arrange
        let directoryURL = URL(fileURLWithPath: "/Users/test/Documents")

        // Act
        let parent = FileItem.parentEntry(for: directoryURL)

        // Assert
        #expect(parent.name == "..")
        #expect(parent.isDirectory == true)
        #expect(parent.isParentDirectory == true)
        #expect(parent.url.path == "/Users/test")
    }

    @Test func defaultInitUsesDefaults() {
        // Arrange & Act
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/test"),
            name: "test",
            isDirectory: true
        )

        // Assert
        #expect(item.size == nil)
        #expect(item.modificationDate == nil)
        #expect(item.creationDate == nil)
        #expect(item.isHidden == false)
        #expect(item.isSymlink == false)
        #expect(item.permissions == 0)
        #expect(item.isParentDirectory == false)
    }

    @Test func hashableConformance() {
        // Arrange
        let item1 = FileItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "a",
            isDirectory: false
        )
        let item2 = FileItem(
            url: URL(fileURLWithPath: "/tmp/b"),
            name: "b",
            isDirectory: false
        )

        // Act
        var set: Set<FileItem> = [item1, item2]
        set.insert(item1) // duplicate — same instance, same UUID

        // Assert — item1 is the same reference so set stays at 2
        #expect(set.count == 2)
    }

    @Test func identifiableWithUniqueIDs() {
        // Arrange & Act
        let item1 = FileItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "a",
            isDirectory: false
        )
        let item2 = FileItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "a",
            isDirectory: false
        )

        // Assert — each instance gets its own UUID
        #expect(item1.id != item2.id)
    }
}
