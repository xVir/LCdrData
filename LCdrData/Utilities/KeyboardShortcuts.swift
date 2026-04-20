import SwiftUI

/// Centralized keyboard shortcut definitions for the file manager.
/// These are applied as `.keyboardShortcut()` modifiers on views.
enum KeyboardShortcuts {

    // MARK: - Navigation

    /// Cmd+Up — go to parent directory
    static let goToParent = KeyboardShortcut(.upArrow, modifiers: .command)

    /// Cmd+Down — open / enter directory
    static let openItem = KeyboardShortcut(.downArrow, modifiers: .command)

    /// Cmd+L — focus path bar
    static let goToPath = KeyboardShortcut("l", modifiers: .command)

    /// Cmd+R — refresh panel
    static let refresh = KeyboardShortcut("r", modifiers: .command)

    /// Cmd+[ — history back
    static let historyBack = KeyboardShortcut("[", modifiers: .command)

    /// Cmd+] — history forward
    static let historyForward = KeyboardShortcut("]", modifiers: .command)

    // MARK: - Selection

    /// Cmd+A — select all
    static let selectAll = KeyboardShortcut("a", modifiers: .command)

    // MARK: - File Operations (Function Keys)
    //
    // SwiftUI's KeyEquivalent doesn't expose F5–F8 as static properties.
    // We define them using Unicode scalar values from the private-use area
    // that macOS uses for function keys (NSF5FunctionKey = 0xF708, etc.).

    /// F5 key equivalent for Copy
    static let f5Key = KeyEquivalent(Character(UnicodeScalar(0xF708)!))

    /// F6 key equivalent for Move
    static let f6Key = KeyEquivalent(Character(UnicodeScalar(0xF709)!))

    /// F7 key equivalent for Mkdir
    static let f7Key = KeyEquivalent(Character(UnicodeScalar(0xF70A)!))

    /// F8 key equivalent for Delete
    static let f8Key = KeyEquivalent(Character(UnicodeScalar(0xF70B)!))

    // MARK: - View

    /// Cmd+Shift+. — toggle hidden files
    static let toggleHidden = KeyboardShortcut(".", modifiers: [.command, .shift])
}
