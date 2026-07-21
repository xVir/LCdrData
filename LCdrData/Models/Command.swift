import Foundation

/// A user action that can be triggered from any UI surface — the window key
/// handler, the menu bar, the command bar, or a context menu — and executed by
/// `CommandRunner`.
///
/// Most cases are parameterless: the runner resolves their target from the
/// active panel's cursor. Cases that carry an explicit payload (`.openItem`,
/// `.rename`) are used where a surface already has the item in hand (e.g. a
/// row double-click or a context menu on a specific row).
enum Command: Equatable {

    // Navigation
    case goToParent
    case back
    case forward
    case goToPath
    case refresh

    // Open / view
    case open
    case openItem(FileItem)
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
