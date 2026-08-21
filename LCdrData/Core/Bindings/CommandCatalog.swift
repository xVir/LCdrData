import SwiftUI
import Models
import Utilities

/// Single source of truth mapping a `Command` to its keyboard shortcut.
///
/// Every UI surface reads its shortcut from here — the window key handler
/// (`keyEquivalent(for:)`), the menu bar and context menu (`shortcut(for:)`),
/// and the command bar — so the bindings cannot drift apart. Titles are
/// intentionally NOT here: surfaces label the same command differently
/// (e.g. "Copy" in the command bar vs. "Copy to Other Panel" in a menu).
package enum CommandCatalog {

    /// The raw key + modifiers bound to a command, if any.
    package static func binding(for command: Command) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        switch command {
        case .goToParent: return (.upArrow, .command)
        case .back: return ("[", .command)
        case .forward: return ("]", .command)
        case .goToPath: return ("l", .command)
        case .refresh: return ("r", .command)

        case .open: return (.downArrow, .command)
        case .openItem: return nil
        case .edit: return (KeyboardShortcuts.f4Key, [])
        case .quickLook: return (KeyboardShortcuts.f3Key, [])

        case .selectAll: return ("a", .command)
        case .deselectAll: return ("a", [.command, .shift])
        case .toggleHidden: return (".", [.command, .shift])

        case .copy: return (KeyboardShortcuts.f5Key, [])
        case .move: return (KeyboardShortcuts.f6Key, [])
        case .newFolder: return (KeyboardShortcuts.f7Key, [])
        case .trash: return (KeyboardShortcuts.f8Key, [])
        case .permanentDelete: return (.delete, .command)
        case .rename: return (KeyboardShortcuts.f2Key, [])

        case .copyPaths: return ("c", [.command, .option])
        case .revealInFinder: return nil
        }
    }

    /// The SwiftUI shortcut for a command, for `.keyboardShortcut(_:)` on menu
    /// and context-menu buttons.
    package static func shortcut(for command: Command) -> KeyboardShortcut? {
        guard let binding = binding(for: command) else { return nil }
        return KeyboardShortcut(binding.key, modifiers: binding.modifiers)
    }

    /// The bare key equivalent for a command, for window-level `.onKeyPress`.
    package static func keyEquivalent(for command: Command) -> KeyEquivalent? {
        binding(for: command)?.key
    }
}
