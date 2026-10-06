import Foundation

/// Bundle identifiers of terminal applications "Open in Terminal" knows how to
/// open in a new tab. Other identifiers are still accepted in configuration;
/// they are handed the folder without a new-tab script.
package nonisolated enum TerminalApplications {
    package static let macOSTerminalBundleID = "com.apple.Terminal"
    package static let ghosttyBundleID = "com.mitchellh.ghostty"
    /// Application name `open -a` accepts for Ghostty.
    package static let ghosttyApplicationName = "Ghostty"
}

/// Which folder "Open in Terminal" acts on for a panel selection.
package enum TerminalTarget {

    /// The directory to open, when the selection is exactly one real folder
    /// or the `..` row. On `..` the folder is the one the panel is showing —
    /// `currentDirectory` — not the parent that row navigates to. Entries
    /// inside an archive are not real folders: their URL is the archive file.
    package static func directory(
        selection: Set<UUID>,
        in listing: [FileItem],
        currentDirectory: URL
    ) -> URL? {
        let selected = listing.filter { selection.contains($0.id) }
        let realItems = selected.filter { !$0.isParentDirectory }

        if realItems.count == 1, let item = realItems.first, isFilesystemDirectory(item) {
            return item.url
        }

        if realItems.isEmpty,
           let parent = selected.first(where: \.isParentDirectory),
           isFilesystemDirectory(parent) {
            return currentDirectory
        }

        return nil
    }

    /// A directory on the filesystem, including a symlink to one.
    package static func isFilesystemDirectory(_ item: FileItem) -> Bool {
        item.isNavigableDirectory && item.archiveContainer == nil
    }
}
