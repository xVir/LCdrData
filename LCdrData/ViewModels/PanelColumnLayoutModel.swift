import Observation
import Models
import Services

/// Owns both panels' column layouts.
///
/// App-wide rather than per-window, so every window agrees about the columns,
/// and separate from `PanelViewModel` because column geometry has no bearing on
/// what is listed, how it is sorted, or where the cursor is.
@Observable
package final class PanelColumnLayoutModel {

    private var left: PanelColumnLayout
    private var right: PanelColumnLayout
    private let store: PanelColumnLayoutStoring

    package init(store: PanelColumnLayoutStoring = PanelColumnLayoutStore()) {
        self.store = store
        let restored = store.load()
        self.left = restored?.left ?? .defaults
        self.right = restored?.right ?? .defaults
    }

    package func layout(for side: PanelSide) -> PanelColumnLayout {
        switch side {
        case .left: left
        case .right: right
        }
    }

    /// Updates a panel's layout in memory only. Called on every frame of a
    /// drag, which is why it deliberately does not persist.
    package func setLayout(_ layout: PanelColumnLayout, for side: PanelSide) {
        switch side {
        case .left: left = layout
        case .right: right = layout
        }
    }

    /// Writes both panels through to storage. Called once, when a drag ends.
    package func commit() {
        store.save(left: left, right: right)
    }
}
