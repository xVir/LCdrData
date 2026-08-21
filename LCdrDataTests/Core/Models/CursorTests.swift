import Testing
import Foundation
@testable import Core

struct CursorTests {

    private static func dir(_ name: String) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isDirectory: true
        )
    }

    private static func file(_ name: String) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isDirectory: false
        )
    }

    private static func parentEntry() -> FileItem {
        FileItem.parentEntry(for: URL(fileURLWithPath: "/tmp"))
    }

    @Test func resolveFreshOnPopulatedListingFocusesFirstRow() {
        // Arrange
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let listing = [parent, alpha]

        // Act
        let result = Cursor.resolve(
            intent: .fresh,
            listing: listing,
            previousListing: [],
            previousCursor: Cursor()
        )

        // Assert
        #expect(result.focused == parent.id)
        #expect(result.selected == [parent.id])
    }

    @Test func resolveKeepSelectionPreservesFocusedAndIntersectsSelected() {
        // Arrange
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        let gamma = Self.file("gamma")
        let listing = [alpha, beta, gamma]
        let previousCursor = Cursor(focused: beta.id, selected: [beta.id, gamma.id])

        // Act
        let result = Cursor.resolve(
            intent: .keepSelection,
            listing: listing,
            previousListing: listing,
            previousCursor: previousCursor
        )

        // Assert
        #expect(result.focused == beta.id)
        #expect(result.selected == [beta.id, gamma.id])
    }

    @Test func resolveLandOnNeighbourOfFocusesItemAfterLastDoomed() {
        // Arrange — beta deleted from a 4-row listing.
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        let gamma = Self.file("gamma")
        let previousListing = [parent, alpha, beta, gamma]
        let newListing = [parent, alpha, gamma]

        // Act
        let result = Cursor.resolve(
            intent: .landOnNeighbourOf([beta.url]),
            listing: newListing,
            previousListing: previousListing,
            previousCursor: Cursor(focused: beta.id, selected: [beta.id])
        )

        // Assert — item after beta was gamma; gamma must receive focus
        #expect(result.focused == gamma.id)
        #expect(result.selected == [gamma.id])
    }

    @Test func resolveLandOnNeighbourOfFallsBackToItemBeforeFirstDoomedAtListEnd() {
        // Arrange — gamma (the last item) deleted.
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        let gamma = Self.file("gamma")
        let previousListing = [parent, alpha, beta, gamma]
        let newListing = [parent, alpha, beta]

        // Act
        let result = Cursor.resolve(
            intent: .landOnNeighbourOf([gamma.url]),
            listing: newListing,
            previousListing: previousListing,
            previousCursor: Cursor(focused: gamma.id, selected: [gamma.id])
        )

        // Assert — no item after gamma; fall back to beta (before gamma)
        #expect(result.focused == beta.id)
        #expect(result.selected == [beta.id])
    }

    // MARK: - Mutation methods

    @Test func selectAllSelectsEveryNonParentRow() {
        // Arrange
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        var cursor = Cursor()

        // Act
        cursor.selectAll(in: [parent, alpha, beta])

        // Assert
        #expect(cursor.selected == [alpha.id, beta.id])
    }

    @Test func focusFirstSkipsParentRow() {
        // Arrange
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        var cursor = Cursor(focused: beta.id, selected: [beta.id])

        // Act
        cursor.focusFirst(in: [parent, alpha, beta])

        // Assert
        #expect(cursor.focused == alpha.id)
        #expect(cursor.selected == [alpha.id])
    }

    @Test func userDidSelectSingleRowSyncsFocused() {
        // Arrange — focused on alpha, user clicks beta.
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        var cursor = Cursor(focused: alpha.id, selected: [alpha.id])

        // Act
        cursor.userDidSelect([beta.id])

        // Assert
        #expect(cursor.focused == beta.id)
        #expect(cursor.selected == [beta.id])
    }

    @Test func userDidSelectEmptyRestoresSelectionFromFocused() {
        // Arrange — user clicked empty space; SwiftUI List wrote an empty set.
        let alpha = Self.dir("alpha")
        var cursor = Cursor(focused: alpha.id, selected: [alpha.id])

        // Act
        cursor.userDidSelect([])

        // Assert — empty selection is rejected; restored to [focused]
        #expect(cursor.focused == alpha.id)
        #expect(cursor.selected == [alpha.id])
    }

    @Test func focusLastSkipsParentRow() {
        // Arrange — non-parent items in middle/end; ".." is at front
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        var cursor = Cursor(focused: alpha.id, selected: [alpha.id])

        // Act
        cursor.focusLast(in: [parent, alpha, beta])

        // Assert
        #expect(cursor.focused == beta.id)
        #expect(cursor.selected == [beta.id])
    }

    @Test func deselectAllKeepingFocusCollapsesSelectedToFocused() {
        // Arrange
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        let gamma = Self.file("gamma")
        var cursor = Cursor(focused: beta.id, selected: [alpha.id, beta.id, gamma.id])

        // Act
        cursor.deselectAllKeepingFocus(in: [alpha, beta, gamma])

        // Assert
        #expect(cursor.focused == beta.id)
        #expect(cursor.selected == [beta.id])
    }

    @Test func resolveLandOnChildFocusesMatchingDirectory() {
        // Arrange — panel just navigated up from /tmp/alpha to /tmp.
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let beta = Self.dir("beta")
        let listing = [parent, alpha, beta]

        // Act
        let result = Cursor.resolve(
            intent: .landOnChild(alpha.url),
            listing: listing,
            previousListing: [],
            previousCursor: Cursor()
        )

        // Assert
        #expect(result.focused == alpha.id)
        #expect(result.selected == [alpha.id])
    }

    @Test func resolveLandOnNewFocusesNewlyCreatedItem() {
        // Arrange — folder "new" just got created.
        let parent = Self.parentEntry()
        let alpha = Self.dir("alpha")
        let new = Self.dir("new")
        let listing = [parent, alpha, new]

        // Act
        let result = Cursor.resolve(
            intent: .landOnNew(new.url),
            listing: listing,
            previousListing: [parent, alpha],
            previousCursor: Cursor(focused: alpha.id, selected: [alpha.id])
        )

        // Assert
        #expect(result.focused == new.id)
        #expect(result.selected == [new.id])
    }

    @Test func resolveKeepSelectionFallsBackToSameIndexWhenFocusedVanished() {
        // Arrange
        let alpha = Self.dir("alpha")
        let beta = Self.file("beta")
        let gamma = Self.file("gamma")
        let previousListing = [alpha, beta, gamma]
        let newListing = [alpha, gamma]  // beta removed
        let previousCursor = Cursor(focused: beta.id, selected: [beta.id])

        // Act
        let result = Cursor.resolve(
            intent: .keepSelection,
            listing: newListing,
            previousListing: previousListing,
            previousCursor: previousCursor
        )

        // Assert — beta was at index 1; new listing[1] = gamma
        #expect(result.focused == gamma.id)
        #expect(result.selected == [gamma.id])
    }
}
