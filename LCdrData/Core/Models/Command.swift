import Foundation

/// A user action that can be triggered from any UI surface — the window key
/// handler, the menu bar, the command bar, or a context menu — and executed by
/// `CommandRunner`.
///
/// Most cases are parameterless: the runner resolves their target from the
/// active panel's cursor. Cases that carry an explicit payload (`.openItem`,
/// `.rename`) are used where a surface already has the item in hand (e.g. a
/// row double-click or a context menu on a specific row).
package enum Command: Equatable {

    // Navigation
    case goToParent
    case back
    case forward
    case goToPath
    case refresh

    // Tabs
    case newTab
    case closeTab
    case nextTab
    case previousTab
    /// The left panel's location, opened as a new front tab on the right.
    case openLeftLocationInRightPanel
    /// The right panel's location, opened as a new front tab on the left.
    case openRightLocationInLeftPanel

    // Open / view
    case open
    case openItem(FileItem)
    /// Open the selected folder in a new tab of the configured terminal.
    /// On the `..` row, that folder is the one the panel is showing.
    case openInTerminal
    case edit
    case quickLook

    // Selection
    case selectAll
    case deselectAll
    case toggleHidden

    // File operations
    case copy
    case move
    case newFolder
    case trash
    case permanentDelete
    case rename(FileItem)

    // Clipboard / Finder
    case copyPaths
    case revealInFinder
}
