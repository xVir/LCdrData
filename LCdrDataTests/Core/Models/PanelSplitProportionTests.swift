import Testing
@testable import Models

struct PanelSplitProportionTests {

    @Test func theMenuListsTheProportionsLeftShareFirst() {
        // Arrange & Act
        let titles = PanelSplitProportion.allCases.map(\.title)

        // Assert — declaration order is the menu order.
        #expect(titles == ["50/50", "60/40", "40/60", "70/30", "30/70"])
    }

    @Test func eachPresetTakesItsShareOfTheSpaceBetweenThePanels() {
        // Arrange — the separator is 1pt, so a 1001pt split has 1000pt to share.
        let expected: [(PanelSplitProportion, Double)] = [
            (.fiftyFifty, 500),
            (.sixtyForty, 600),
            (.fortySixty, 400),
            (.seventyThirty, 700),
            (.thirtySeventy, 300),
        ]

        // Act & Assert
        for (proportion, width) in expected {
            #expect(
                proportion.leftPanelWidth(
                    totalWidth: 1001,
                    dividerThickness: 1,
                    minimumPanelWidth: 300
                ) == width
            )
        }
    }

    @Test func aWideLeftPresetStopsSoTheRightPanelKeepsItsMinimum() {
        // Arrange — 70% of 1000 is 700, which would leave the right panel 300,
        // short of the 400 it must keep.
        let proportion = PanelSplitProportion.seventyThirty

        // Act
        let width = proportion.leftPanelWidth(
            totalWidth: 1000,
            dividerThickness: 0,
            minimumPanelWidth: 400
        )

        // Assert
        #expect(width == 600)
    }

    @Test func aWideRightPresetStopsSoTheLeftPanelKeepsItsMinimum() {
        // Arrange — 30% of 1000 is 300, under the left panel's minimum of 400.
        let proportion = PanelSplitProportion.thirtySeventy

        // Act
        let width = proportion.leftPanelWidth(
            totalWidth: 1000,
            dividerThickness: 0,
            minimumPanelWidth: 400
        )

        // Assert
        #expect(width == 400)
    }

    @Test func draggingPastEitherMinimumLandsOnThatMinimum() {
        // Arrange
        let totalWidth = 1000.0
        let minimum = 300.0

        // Act
        let tooNarrow = PanelSplitProportion.leftShare(
            forLeftWidth: 40,
            totalWidth: totalWidth,
            dividerThickness: 0,
            minimumPanelWidth: minimum
        )
        let tooWide = PanelSplitProportion.leftShare(
            forLeftWidth: 990,
            totalWidth: totalWidth,
            dividerThickness: 0,
            minimumPanelWidth: minimum
        )

        // Assert — the stored share reproduces the clamped width, not the
        // pointer position past the stop.
        #expect(PanelSplitProportion.leftPanelWidth(
            share: tooNarrow,
            totalWidth: totalWidth,
            dividerThickness: 0,
            minimumPanelWidth: minimum
        ) == minimum)
        #expect(PanelSplitProportion.leftPanelWidth(
            share: tooWide,
            totalWidth: totalWidth,
            dividerThickness: 0,
            minimumPanelWidth: minimum
        ) == totalWidth - minimum)
    }

    @Test func aNarrowWindowSplitsTheRemainderEvenly() {
        // Arrange — 500pt cannot give both panels their 300pt minimum.
        let proportion = PanelSplitProportion.seventyThirty

        // Act
        let width = proportion.leftPanelWidth(
            totalWidth: 500,
            dividerThickness: 0,
            minimumPanelWidth: 300
        )

        // Assert
        #expect(width == 250)
    }
}
