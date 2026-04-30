import SwiftUI

// MARK: - Environment (handler must run on the focused `List`, not only on `MainWindowView`)

private struct NameFilterKeyPressHandlerKey: EnvironmentKey {
    static let defaultValue: ((KeyPress) -> KeyPress.Result)? = nil
}

extension EnvironmentValues {
    /// When the name filter bar is open, character keys are handled on the file `List` (first responder) via this closure.
    var nameFilterKeyPressHandler: ((KeyPress) -> KeyPress.Result)? {
        get { self[NameFilterKeyPressHandlerKey.self] }
        set { self[NameFilterKeyPressHandlerKey.self] = newValue }
    }
}

// MARK: - Logic shared with `MainWindowView` type-ahead routing

enum NameFilterKeyPress {

    /// Append one allowed character to the filter, or return `.ignored` (arrows, shortcuts, etc.).
    static func handle(
        press: KeyPress,
        panel: PanelViewModel,
        keyboardRoutingActive: Bool
    ) -> KeyPress.Result {
        guard keyboardRoutingActive else { return .ignored }
        guard !panel.isPathBarEditing else { return .ignored }
        guard panel.isFilterBarVisible else { return .ignored }

        if press.modifiers.contains(.command)
            || press.modifiers.contains(.control)
            || press.modifiers.contains(.option) {
            return .ignored
        }
        if keyEquivalentIsNonTextNavigation(press.key) {
            return .ignored
        }
        let chars = press.characters
        guard chars.count == 1, let scalar = chars.unicodeScalars.first else {
            return .ignored
        }
        guard unicodeScalarIsAllowedInFilter(scalar) else {
            return .ignored
        }
        panel.appendToNameFilter(String(chars))
        return .handled
    }

    /// Arrow and other navigation keys can still deliver a non-control `characters` value; never treat those as filter input.
    private static func keyEquivalentIsNonTextNavigation(_ key: KeyEquivalent) -> Bool {
        if key == .upArrow || key == .downArrow || key == .leftArrow || key == .rightArrow {
            return true
        }
        if key == .home || key == .end || key == .pageUp || key == .pageDown {
            return true
        }
        if key == .tab || key == .return || key == .escape {
            return true
        }
        if key == .delete || key == .deleteForward {
            return true
        }
        if key == KeyboardShortcuts.f2Key || key == KeyboardShortcuts.f3Key || key == KeyboardShortcuts.f4Key
            || key == KeyboardShortcuts.f5Key || key == KeyboardShortcuts.f6Key || key == KeyboardShortcuts.f7Key
            || key == KeyboardShortcuts.f8Key {
            return true
        }
        return false
    }

    /// Only letters, numbers, ordinary punctuation/symbols, combining marks, and spaces — excludes controls,
    /// private-use (incl. Apple function-key codes), format chars, line/paragraph separators, etc.
    private static func unicodeScalarIsAllowedInFilter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber,
             .spaceSeparator,
             .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        case .lineSeparator, .paragraphSeparator,
             .control, .format, .surrogate, .privateUse, .unassigned:
            return false
        @unknown default:
            return false
        }
    }
}
