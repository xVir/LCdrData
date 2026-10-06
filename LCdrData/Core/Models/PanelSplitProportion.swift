import Foundation

/// A fixed way to share the width between the left and right file panels.
///
/// The title is `left/right`, so `.sixtyForty` is "60/40": the left panel
/// takes 60% of the space between the panels and the right panel takes the
/// rest. The separator itself is not part of that space.
package nonisolated enum PanelSplitProportion: CaseIterable, Equatable, Hashable, Sendable {
    case fiftyFifty
    case sixtyForty
    case fortySixty
    case seventyThirty
    case thirtySeventy

    /// Whole percent of the space between the panels that the left one takes.
    private var leftPercent: Int {
        switch self {
        case .fiftyFifty: 50
        case .sixtyForty: 60
        case .fortySixty: 40
        case .seventyThirty: 70
        case .thirtySeventy: 30
        }
    }

    /// Fraction of the space between the panels that the left one takes.
    /// A drag writes an arbitrary share; a menu choice writes one of these.
    package var leftShare: Double { Double(leftPercent) / 100 }

    /// The menu title, `left/right`.
    package var title: String { "\(leftPercent)/\(100 - leftPercent)" }

    /// Width of the left panel for this proportion.
    package func leftPanelWidth(
        totalWidth: Double,
        dividerThickness: Double,
        minimumPanelWidth: Double
    ) -> Double {
        Self.leftPanelWidth(
            share: leftShare,
            totalWidth: totalWidth,
            dividerThickness: dividerThickness,
            minimumPanelWidth: minimumPanelWidth
        )
    }

    /// Width of the left panel for an arbitrary share, including one a drag
    /// produced. Each panel keeps `minimumPanelWidth` when the window is wide
    /// enough; when it is not, the two panels split whatever is left.
    package static func leftPanelWidth(
        share: Double,
        totalWidth: Double,
        dividerThickness: Double,
        minimumPanelWidth: Double
    ) -> Double {
        let available = availableWidth(totalWidth: totalWidth, dividerThickness: dividerThickness)
        return clamped(
            preferred: available * share,
            available: available,
            minimumPanelWidth: minimumPanelWidth
        )
    }

    /// The share a drag should store so the next layout reproduces `preferred`
    /// left-panel width, after the minimums have been applied.
    package static func leftShare(
        forLeftWidth preferred: Double,
        totalWidth: Double,
        dividerThickness: Double,
        minimumPanelWidth: Double
    ) -> Double {
        let available = availableWidth(totalWidth: totalWidth, dividerThickness: dividerThickness)
        guard available > 0 else { return fiftyFifty.leftShare }
        let width = clamped(
            preferred: preferred,
            available: available,
            minimumPanelWidth: minimumPanelWidth
        )
        return width / available
    }

    private static func availableWidth(totalWidth: Double, dividerThickness: Double) -> Double {
        max(0, totalWidth - max(0, dividerThickness))
    }

    private static func clamped(
        preferred: Double,
        available: Double,
        minimumPanelWidth: Double
    ) -> Double {
        let minimum = max(0, minimumPanelWidth)
        let lower = min(minimum, available / 2)
        let upper = max(available - minimum, lower)
        return min(max(preferred, lower), upper)
    }
}
