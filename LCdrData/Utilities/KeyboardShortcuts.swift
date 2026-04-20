//
//  KeyboardShortcuts.swift
//  LCdrData
//
//  Created by Dima Skachkov on 02.04.2026.
//

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

    // MARK: - View

    /// Cmd+Shift+. — toggle hidden files
    static let toggleHidden = KeyboardShortcut(".", modifiers: [.command, .shift])
}
