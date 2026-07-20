import AppKit
import SwiftUI

/// Context-menu content for a panel, shown on **secondary click**.
///
/// Renders one of three variants chosen by `FileContextMenuModel`:
/// selection (real items), parent (`..` row), or background (empty area).
/// The panel has already been made the **active panel** by the time this menu
/// opens (activation happens in the list's selection binding), so file
/// operations run against `appState.activePanelViewModel` / `inactivePanelViewModel`.
///
/// Keyboard-shortcut hints are **display-only** — rendered as text, never via
/// `.keyboardShortcut`, to avoid registering a second command that would
/// collide with the existing `onKeyPress` F-key routing in `MainWindowView`.
struct FileContextMenu: View {

    let model: FileContextMenuModel
    let panel: PanelViewModel
    let appState: AppState

    var body: some View {
        switch model.variant {
        case .selection:
            selectionMenu
        case .parent:
            parentMenu
        case .background:
            backgroundMenu
        }
    }

    // MARK: - Selection variant

    @ViewBuilder
    private var selectionMenu: some View {
        if model.isSingleSelection {
            menuButton("Open", hint: "⌘↓") {
                Task { await appState.activePanelViewModel.openSelectedItem() }
            }
            Divider()
        }

        menuButton("Move to Trash", hint: "F8") {
            appState.fileOperations.requestDelete(from: appState.activePanelViewModel)
        }

        if let item = model.singleItem {
            menuButton("Rename\u{2026}", hint: "F2") {
                appState.fileOperations.requestRename(item: item)
            }
        }

        Divider()

        menuButton("Copy to Other Panel", hint: "F5") {
            appState.fileOperations.requestCopy(
                from: appState.activePanelViewModel,
                to: appState.inactivePanelViewModel
            )
        }

        menuButton("Move to Other Panel", hint: "F6") {
            appState.fileOperations.requestMove(
                from: appState.activePanelViewModel,
                to: appState.inactivePanelViewModel
            )
        }

        Divider()

        menuButton("Copy Path") {
            appState.copySelectedPathsToPasteboard()
        }

        menuButton("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(model.urls)
        }

        // MARK: - LCdrData actions (extension point)
        // App-specific context-menu items go here, e.g.:
        //   Divider()
        //   menuButton("Compare\u{2026}") { ... }
    }

    // MARK: - Parent variant

    @ViewBuilder
    private var parentMenu: some View {
        menuButton("Open") {
            Task { await panel.navigateToParent() }
        }
    }

    // MARK: - Background variant

    @ViewBuilder
    private var backgroundMenu: some View {
        menuButton("New Folder", hint: "F7") {
            appState.fileOperations.requestNewFolder()
        }

        menuButton("Select All", hint: "⌘A") {
            panel.selectAll()
        }

        Divider()

        menuButton("Toggle Hidden Files") {
            Task { await panel.toggleHiddenFiles() }
        }

        menuButton("Reload") {
            Task { await panel.reload(.keepSelection) }
        }
    }

    // MARK: - Helpers

    /// A menu button whose label optionally carries a display-only shortcut
    /// hint (tab-separated so it trails the title). The hint is never a real
    /// `.keyboardShortcut`.
    @ViewBuilder
    private func menuButton(
        _ title: String,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if let hint {
                Text(verbatim: "\(title)\t\(hint)")
            } else {
                Text(verbatim: title)
            }
        }
    }
}
