import Testing
import Foundation
@testable import Models

struct PanelColumnLayoutTests {

    @Test func aFreshLayoutShowsTheFourColumnsInCanonicalOrder() {
        // Arrange & Act
        let layout = PanelColumnLayout.defaults

        // Assert
        #expect(layout.columns == [.name, .size, .dateModified, .kind])
    }

    @Test func nameAbsorbsWhateverTheOtherColumnsLeaveOver() {
        // Arrange — the three fixed columns come to 80 + 140 + 80 = 300.
        let layout = PanelColumnLayout.defaults

        // Act
        let widths = layout.resolvedWidths(availableWidth: 800)

        // Assert
        #expect(widths == [500, 80, 140, 80])
        #expect(widths.reduce(0, +) == 800)
    }

    @Test func nameStopsAtItsMinimumRatherThanCollapsingOnANarrowPanel() {
        // Arrange — 300pt of fixed columns in a 320pt panel leaves 20 for Name.
        let layout = PanelColumnLayout.defaults

        // Act
        let widths = layout.resolvedWidths(availableWidth: 320)

        // Assert
        #expect(widths[0] == FileColumn.name.minimumWidth)
    }

    @Test func draggingADividerMovesThatDividerAndLeavesTheOthersWhereTheyWere() {
        // Arrange
        let layout = PanelColumnLayout.defaults

        // Act — drag the divider after Size (index 1) 30pt to the right.
        let resized = layout.resizing(dividerAfter: 1, by: 30, availableWidth: 800)

        // Assert — Size grew by 30 and Date Modified gave the same 30 back, so
        // the dragged divider moved 30pt and every other one stayed put. Name
        // is untouched: charging it instead would pin the divider under the
        // pointer in place and move the one after Name.
        #expect(resized.resolvedWidths(availableWidth: 800) == [500, 110, 110, 80])
        #expect(resized.columns == layout.columns)
    }

    @Test func draggingADividerKeepsTheTotalPinnedToThePanel() {
        // Arrange
        let layout = PanelColumnLayout.defaults

        // Act
        let resized = layout.resizing(dividerAfter: 2, by: -25, availableWidth: 640)

        // Assert
        let widths = resized.resolvedWidths(availableWidth: 640)
        #expect(widths == [340, 80, 115, 105])
        #expect(widths.reduce(0, +) == 640)
    }

    @Test func shrinkingAColumnStopsAtItsMinimumWidth() {
        // Arrange — Size starts at 80 with a minimum of 48.
        let layout = PanelColumnLayout.defaults

        // Act — drag far further left than the column can give.
        let resized = layout.resizing(dividerAfter: 1, by: -500, availableWidth: 800)

        // Assert
        #expect(resized.resolvedWidths(availableWidth: 800)[1] == FileColumn.size.minimumWidth)
    }

    @Test func wideningStopsOnceTheColumnOnTheRightHasNothingLeftToGive() {
        // Arrange — Date Modified starts at 140 with a minimum of 80, so it can
        // only hand Size 60 no matter how far the drag goes.
        let layout = PanelColumnLayout.defaults

        // Act — ask for far more than that.
        let resized = layout.resizing(dividerAfter: 1, by: 400, availableWidth: 500)

        // Assert
        let widths = resized.resolvedWidths(availableWidth: 500)
        #expect(widths == [200, 140, 80, 80])
        #expect(widths.reduce(0, +) == 500)
    }

    @Test func theDividerAfterNameResizesTheColumnToItsRight() {
        // Arrange — Name is the slack column and has no width of its own, so
        // its divider has to act on its neighbour instead.
        let layout = PanelColumnLayout.defaults

        // Act — drag the divider after Name (index 0) 30pt right, which should
        // grow Name by 30 and take 30 off Size.
        let resized = layout.resizing(dividerAfter: 0, by: 30, availableWidth: 800)

        // Assert
        #expect(resized.resolvedWidths(availableWidth: 800) == [530, 50, 140, 80])
    }

    @Test func wideningNameStopsOnceItsNeighbourReachesItsMinimum() {
        // Arrange
        let layout = PanelColumnLayout.defaults

        // Act — drag Name's divider far past what Size can give up.
        let resized = layout.resizing(dividerAfter: 0, by: 400, availableWidth: 500)

        // Assert — Size sat down on its 48pt minimum and Name took the rest.
        let widths = resized.resolvedWidths(availableWidth: 500)
        #expect(widths == [232, 48, 140, 80])
        #expect(widths.reduce(0, +) == 500)
    }

    // MARK: - Reordering

    @Test func movingAColumnLaterPutsItAtTheRequestedIndexAndCarriesItsWidth() {
        // Arrange
        let layout = PanelColumnLayout.defaults

        // Act — Size (index 1) to the end.
        let moved = layout.moving(from: 1, to: 3)

        // Assert
        #expect(moved.columns == [.name, .dateModified, .kind, .size])
        #expect(moved.resolvedWidths(availableWidth: 800) == [500, 140, 80, 80])
    }

    @Test func aHeaderDraggedShortOfItsNeighbourStaysPut() {
        // Arrange — widths [500, 80, 140, 80]; Size must travel past the middle
        // of Date Modified before it has earned the swap.
        let layout = PanelColumnLayout.defaults
        let widths = layout.resolvedWidths(availableWidth: 800)

        // Act
        let target = layout.targetIndex(draggedIndex: 1, translationX: 40, widths: widths)

        // Assert
        #expect(target == 1)
    }

    @Test func aHeaderDraggedPastItsNeighboursCentreTakesThatSlot() {
        // Arrange — widths [500, 80, 140, 80]. Size sits centred at 540 and
        // Date Modified at 650, so 120pt of travel clears the halfway point.
        let layout = PanelColumnLayout.defaults
        let widths = layout.resolvedWidths(availableWidth: 800)

        // Act
        let target = layout.targetIndex(draggedIndex: 1, translationX: 120, widths: widths)

        // Assert
        #expect(target == 2)
    }

    @Test func aHeaderDraggedFarPastTheEndClampsToTheLastSlot() {
        // Arrange
        let layout = PanelColumnLayout.defaults
        let widths = layout.resolvedWidths(availableWidth: 800)

        // Act
        let target = layout.targetIndex(draggedIndex: 1, translationX: 5000, widths: widths)

        // Assert
        #expect(target == 3)
    }

    @Test func aHeaderDraggedLeftPastItsNeighbourTakesTheEarlierSlot() {
        // Arrange — Date Modified is centred at 650, Size at 540.
        let layout = PanelColumnLayout.defaults
        let widths = layout.resolvedWidths(availableWidth: 800)

        // Act
        let target = layout.targetIndex(draggedIndex: 2, translationX: -120, widths: widths)

        // Assert
        #expect(target == 1)
    }

    // MARK: - Surviving stored data

    @Test func aStoredLayoutMissingAColumnGetsItBackAtTheEnd() {
        // Arrange — data written before Kind existed, say.
        let stored = [
            PanelColumnLayout.Entry(column: .name, width: 0),
            PanelColumnLayout.Entry(column: .size, width: 90)
        ]

        // Act
        let layout = PanelColumnLayout(sanitizing: stored)

        // Assert — the known columns keep their order and widths, the rest are
        // appended rather than the layout being thrown away.
        #expect(layout.columns == [.name, .size, .dateModified, .kind])
        #expect(layout.resolvedWidths(availableWidth: 800)[1] == 90)
    }

    @Test func aStoredLayoutNamingTheSameColumnTwiceKeepsOnlyTheFirst() {
        // Arrange
        let stored = [
            PanelColumnLayout.Entry(column: .size, width: 90),
            PanelColumnLayout.Entry(column: .size, width: 200)
        ]

        // Act
        let layout = PanelColumnLayout(sanitizing: stored)

        // Assert
        #expect(layout.columns == [.size, .name, .dateModified, .kind])
        #expect(layout.resolvedWidths(availableWidth: 800)[0] == 90)
    }

    @Test func aStoredWidthBelowTheMinimumIsRaisedToIt() {
        // Arrange — a width no drag could have produced.
        let stored = [PanelColumnLayout.Entry(column: .size, width: 1)]

        // Act
        let layout = PanelColumnLayout(sanitizing: stored)

        // Assert
        #expect(layout.resolvedWidths(availableWidth: 800)[0] == FileColumn.size.minimumWidth)
    }
}
