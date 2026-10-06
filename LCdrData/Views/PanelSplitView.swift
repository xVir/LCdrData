import AppKit
import SwiftUI
import Models

/// The two file panels and the splitter between them.
///
/// The split is stored as the left panel's share of the width, so it holds
/// when the window is resized. Dragging the separator writes a new share; a
/// secondary click offers the fixed proportions.
struct PanelSplitView<Left: View, Right: View>: View {

    private var left: Left
    private var right: Right

    @State private var leftShare: Double = PanelSplitProportion.fiftyFifty.leftShare

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let resolvedLeftWidth = leftWidth(totalWidth: totalWidth)
            HStack(spacing: 0) {
                left
                    .frame(width: resolvedLeftWidth)
                Rectangle()
                    .fill(.separator)
                    .frame(width: PanelSplitMetrics.dividerThickness)
                    .frame(maxHeight: .infinity)
                right
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // The coordinate space has to enclose the hit target. The target
            // rides the separator, so a translation measured in its own space
            // is taken from a moving origin and the divider runs away.
            .overlay(alignment: .topLeading) {
                PanelSeparatorControl(
                    totalWidth: totalWidth,
                    leftWidth: resolvedLeftWidth,
                    leftShare: $leftShare
                )
                .frame(width: PanelSplitMetrics.hitWidth, height: geo.size.height)
                .offset(x: separatorHitOrigin(leftWidth: resolvedLeftWidth))
            }
            .coordinateSpace(PanelSplitMetrics.coordinateSpace)
        }
    }

    private func leftWidth(totalWidth: CGFloat) -> CGFloat {
        CGFloat(PanelSplitProportion.leftPanelWidth(
            share: leftShare,
            totalWidth: Double(totalWidth),
            dividerThickness: Double(PanelSplitMetrics.dividerThickness),
            minimumPanelWidth: Double(PanelSplitMetrics.minimumPanelWidth)
        ))
    }

    /// Leading edge of the hit strip, centering it on the drawn separator.
    private func separatorHitOrigin(leftWidth: CGFloat) -> CGFloat {
        leftWidth + (PanelSplitMetrics.dividerThickness - PanelSplitMetrics.hitWidth) / 2
    }
}

/// Grab target for the panel separator. Wider than the hairline it sits on,
/// so a secondary click can land; the extra width does not take layout space.
private struct PanelSeparatorControl: View {

    let totalWidth: CGFloat
    let leftWidth: CGFloat
    @Binding var leftShare: Double

    /// The left-panel width when this drag began. `translation` is cumulative
    /// from the pointer-down, so applying it to the live width every frame
    /// compounds and the separator runs away.
    @State private var dragBaseline: CGFloat?
    @State private var isHovering = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                // push/pop must balance: without the flag a missed exit — the
                // pointer leaving the window fast — leaks a pushed cursor.
                guard inside != isHovering else { return }
                isHovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
            .gesture(drag)
            .contextMenu {
                ForEach(PanelSplitProportion.allCases, id: \.self) { proportion in
                    Button(proportion.title) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            leftShare = proportion.leftShare
                        }
                    }
                }
            }
            .accessibilityLabel("Panel separator")
            .accessibilityIdentifier("panelSeparator")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: PanelSplitMetrics.coordinateSpace)
            .onChanged { value in
                let base = dragBaseline ?? leftWidth
                dragBaseline = base
                leftShare = PanelSplitProportion.leftShare(
                    forLeftWidth: Double(base + value.translation.width),
                    totalWidth: Double(totalWidth),
                    dividerThickness: Double(PanelSplitMetrics.dividerThickness),
                    minimumPanelWidth: Double(PanelSplitMetrics.minimumPanelWidth)
                )
            }
            .onEnded { _ in
                dragBaseline = nil
            }
    }
}

private enum PanelSplitMetrics {
    static let minimumPanelWidth: CGFloat = 300
    static let dividerThickness: CGFloat = 1
    /// The drawn separator is a hairline. The grab strip is wider so it can
    /// be dragged and secondary-clicked, and it is centered on that hairline
    /// rather than inserted into the layout.
    static let hitWidth: CGFloat = 8
    static let coordinateSpace = NamedCoordinateSpace.named("panelSplit")
}
