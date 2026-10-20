import Darwin
import Foundation

/// Supplies the user's real home directory. Injectable so tests can pin a home
/// directory instead of depending on the account the suite runs as.
package nonisolated protocol HomeDirectoryProviding: Sendable {
    var homeDirectory: URL { get }
}

/// Reads the home directory from the account database.
///
/// `NSHomeDirectory()` — and with it `FileManager.homeDirectoryForCurrentUser`
/// and `NSString.expandingTildeInPath` — report the **sandbox container**
/// (`~/Library/Containers/com.xvir.LCdrData/Data`) rather than the account's
/// home. That is the right answer for the app's own storage and the wrong one
/// for paths the user wrote, where `~` means their actual home. `getpwuid`
/// reports the real home and stays readable from inside the sandbox.
package nonisolated struct AccountHomeDirectoryProvider: HomeDirectoryProviding {
    package var homeDirectory: URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        let path = FileManager.default.string(
            withFileSystemRepresentation: directory,
            length: strlen(directory)
        )
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Resolves a leading `~` in a path the user authored — configured favorites and
/// the Cmd+L path field — against their real home directory.
///
/// Only `~` and `~/…` are expanded. A `~user` form is left alone rather than
/// guessed at, and any other path is passed through untouched.
package nonisolated struct TildePathExpander: Sendable {

    private let home: HomeDirectoryProviding

    package init(home: HomeDirectoryProviding = AccountHomeDirectoryProvider()) {
        self.home = home
    }

    /// The directory URL `path` denotes, with a leading tilde expanded.
    package func expand(_ path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)

        guard trimmed == "~" || trimmed.hasPrefix("~/") else {
            return URL(fileURLWithPath: trimmed, isDirectory: true)
        }

        let remainder = String(trimmed.dropFirst(2))
        guard !remainder.isEmpty else { return home.homeDirectory }
        return home.homeDirectory.appendingPathComponent(remainder, isDirectory: true)
    }

    /// The real home directory `~` stands for.
    package var homeDirectory: URL { home.homeDirectory }

    /// Writes a path inside the real home folder as `~` or `~/…`. A path outside
    /// that folder is returned unchanged. `~` is not applied to a path that only
    /// shares a prefix with home (`/Users/name` does not abbreviate `/Users/name-extra`).
    package func abbreviate(_ absolutePath: String) -> String {
        let homePath = Self.normalized(home.homeDirectory.path)
        let path = Self.normalized(absolutePath)
        if path == homePath { return "~" }
        let prefix = homePath + "/"
        guard path.hasPrefix(prefix) else { return absolutePath }
        return "~/" + path.dropFirst(prefix.count)
    }

    private static func normalized(_ path: String) -> String {
        var path = URL(fileURLWithPath: path).path
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
