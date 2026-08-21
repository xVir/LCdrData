import AppKit
import SwiftUI
import Core
import Services
import ViewModels
import AppEnvironment

/// Context-menu content for a panel, shown on **secondary click**.
///
/// Renders one of three variants chosen by `FileContextMenuModel`:
/// selection (real items), parent (`..` row), or background (empty area).
/// The panel has already been made the **active panel** by the time this menu
/// opens (activation happens in the list's selection binding), so all actions
/// run through `appState.commands`, which targets the active panel.
///
/// Keyboard-shortcut hints come from `CommandCatalog` (the single source of
/// truth) via `.keyboardShortcut`, so macOS renders them trailing, right-
/// aligned, and grey. Shortcuts declared inside a `.contextMenu` are ephemeral
/// (the content exists only while the menu is open), so they are not registered
/// globally and do not collide with the window's `onKeyPress` routing.
package struct FileContextMenu: View {

    package let model: FileContextMenuModel
    package let appState: AppState

    package var body: some View {
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
            menuButton("Open", command: .open)
            Divider()
        }

        menuButton("Move to Trash", command: .trash)

        if let item = model.singleItem {
            menuButton("Rename\u{2026}", command: .rename(item))
        }

        Divider()

        menuButton("Copy to Other Panel", command: .copy)
        menuButton("Move to Other Panel", command: .move)

        Divider()

        menuButton("Copy Path", command: .copyPaths)
        menuButton("Reveal in Finder", command: .revealInFinder)

        // MARK: - LCdrData actions (extension point)
        // App-specific context-menu items go here.
    }

    // MARK: - Parent variant

    @ViewBuilder
    private var parentMenu: some View {
        menuButton("Open", command: .goToParent)
    }

    // MARK: - Background variant

    @ViewBuilder
    private var backgroundMenu: some View {
        menuButton("New Folder", command: .newFolder)
        menuButton("Select All", command: .selectAll)
        Divider()
        menuButton("Toggle Hidden Files", command: .toggleHidden)
        menuButton("Reload", command: .refresh)
    }

    // MARK: - Helpers

    /// A menu button that runs a `Command` and shows its catalog shortcut as
    /// native trailing grey text.
    @ViewBuilder
    private func menuButton(_ title: String, command: Command) -> some View {
        Button(title) {
            appState.commands.perform(command)
        }
        .keyboardShortcut(CommandCatalog.shortcut(for: command))
    }
}
