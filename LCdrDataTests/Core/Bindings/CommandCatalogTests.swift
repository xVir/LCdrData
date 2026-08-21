import Testing
import SwiftUI
@testable import Bindings
@testable import Models
@testable import Utilities

struct CommandCatalogTests {

    private func makeItem(path: String = "/tmp/file.txt") -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: path),
            name: (path as NSString).lastPathComponent,
            isDirectory: false
        )
    }

    // MARK: - Function keys

    @Test func fileOperationsUseBareFunctionKeys() {
        let expected: [(Command, KeyEquivalent)] = [
            (.quickLook, KeyboardShortcuts.f3Key),
            (.edit, KeyboardShortcuts.f4Key),
            (.copy, KeyboardShortcuts.f5Key),
            (.move, KeyboardShortcuts.f6Key),
            (.newFolder, KeyboardShortcuts.f7Key),
            (.trash, KeyboardShortcuts.f8Key),
            (.rename(makeItem()), KeyboardShortcuts.f2Key),
        ]

        for (command, key) in expected {
            let binding = CommandCatalog.binding(for: command)
            #expect(binding?.key == key)
            #expect(binding?.modifiers == [])
        }
    }

    // MARK: - Modifier combinations

    @Test func navigationCommandsUseCommandModifier() {
        #expect(CommandCatalog.binding(for: .goToParent)?.key == .upArrow)
        #expect(CommandCatalog.binding(for: .goToParent)?.modifiers == .command)
        #expect(CommandCatalog.binding(for: .open)?.key == .downArrow)
        #expect(CommandCatalog.binding(for: .back)?.key == "[")
        #expect(CommandCatalog.binding(for: .forward)?.key == "]")
    }

    @Test func selectAllAndDeselectAllShareAKeyAndDifferByShift() {
        let selectAll = CommandCatalog.binding(for: .selectAll)
        let deselectAll = CommandCatalog.binding(for: .deselectAll)

        #expect(selectAll?.key == "a")
        #expect(deselectAll?.key == "a")
        #expect(selectAll?.modifiers == .command)
        #expect(deselectAll?.modifiers == [.command, .shift])
    }

    @Test func permanentDeleteIsCommandDelete() {
        let binding = CommandCatalog.binding(for: .permanentDelete)
        #expect(binding?.key == .delete)
        #expect(binding?.modifiers == .command)
    }

    // MARK: - Commands without a shortcut

    @Test func openItemHasNoBindingOfItsOwn() {
        let item = makeItem()

        #expect(CommandCatalog.binding(for: .openItem(item)) == nil)
        #expect(CommandCatalog.shortcut(for: .openItem(item)) == nil)
        #expect(CommandCatalog.keyEquivalent(for: .openItem(item)) == nil)
    }

    @Test func revealInFinderHasNoBinding() {
        #expect(CommandCatalog.binding(for: .revealInFinder) == nil)
    }

    // MARK: - Derived accessors agree with the binding

    @Test func keyEquivalentMatchesTheBindingKey() {
        #expect(CommandCatalog.keyEquivalent(for: .refresh) == CommandCatalog.binding(for: .refresh)?.key)
        #expect(CommandCatalog.keyEquivalent(for: .copy) == CommandCatalog.binding(for: .copy)?.key)
    }

    @Test func shortcutIsNonNilExactlyWhenABindingExists() {
        #expect(CommandCatalog.shortcut(for: .goToPath) != nil)
        #expect(CommandCatalog.shortcut(for: .revealInFinder) == nil)
    }
}
