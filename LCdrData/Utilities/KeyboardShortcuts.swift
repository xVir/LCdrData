import SwiftUI

/// Low-level key primitives that SwiftUI does not expose as `KeyEquivalent`
/// statics (the function keys F2–F8). The mapping from a `Command` to its
/// shortcut lives in `CommandCatalog`; this enum only defines the raw keys the
/// catalog and the window key handler build on.
enum KeyboardShortcuts {

    // MARK: - Function Keys
    //
    // SwiftUI's KeyEquivalent doesn't expose F2–F8 as static properties.
    // We define them using Unicode scalar values from the private-use area
    // that macOS uses for function keys (NSF5FunctionKey = 0xF708, etc.).

    /// F2 key equivalent for Rename
    static let f2Key = KeyEquivalent(Character(UnicodeScalar(0xF705)!))

    /// F3 key equivalent for Quick Look
    static let f3Key = KeyEquivalent(Character(UnicodeScalar(0xF706)!))

    /// F4 key equivalent for Edit / open
    static let f4Key = KeyEquivalent(Character(UnicodeScalar(0xF707)!))

    /// F5 key equivalent for Copy
    static let f5Key = KeyEquivalent(Character(UnicodeScalar(0xF708)!))

    /// F6 key equivalent for Move
    static let f6Key = KeyEquivalent(Character(UnicodeScalar(0xF709)!))

    /// F7 key equivalent for Mkdir
    static let f7Key = KeyEquivalent(Character(UnicodeScalar(0xF70A)!))

    /// F8 key equivalent for Delete
    static let f8Key = KeyEquivalent(Character(UnicodeScalar(0xF70B)!))
}
