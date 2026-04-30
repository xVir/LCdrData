import Foundation

/// Persists and restores the last-used directory paths for both panels, optionally via security-scoped bookmarks.
protocol PanelPathStoreProtocol: Sendable {
    func save(leftPath: String, rightPath: String, leftBookmark: Data?, rightBookmark: Data?)
    func restore() -> (left: URL, right: URL)?
}

/// Stores panel paths and optional app-scope bookmarks in `UserDefaults`.
final class PanelPathStore: PanelPathStoreProtocol, Sendable {

    private static let leftKey = "panelPath.left"
    private static let rightKey = "panelPath.right"
    private static let leftBookmarkKey = "panelBookmark.left"
    private static let rightBookmarkKey = "panelBookmark.right"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(leftPath: String, rightPath: String, leftBookmark: Data?, rightBookmark: Data?) {
        defaults.set(leftPath, forKey: Self.leftKey)
        defaults.set(rightPath, forKey: Self.rightKey)
        if let leftBookmark {
            defaults.set(leftBookmark, forKey: Self.leftBookmarkKey)
        }
        if let rightBookmark {
            defaults.set(rightBookmark, forKey: Self.rightBookmarkKey)
        }
    }

    func restore() -> (left: URL, right: URL)? {
        if let pair = restoreFromBookmarks() {
            return pair
        }
        return restoreFromPathsOnly()
    }

    private func restoreFromBookmarks() -> (left: URL, right: URL)? {
        guard let leftData = defaults.data(forKey: Self.leftBookmarkKey),
              let rightData = defaults.data(forKey: Self.rightBookmarkKey),
              let leftURL = BookmarkService.url(fromBookmarkData: leftData),
              let rightURL = BookmarkService.url(fromBookmarkData: rightData) else {
            return nil
        }

        let fm = FileManager.default
        var leftIsDir: ObjCBool = false
        var rightIsDir: ObjCBool = false
        let leftExists = fm.fileExists(atPath: leftURL.path, isDirectory: &leftIsDir) && leftIsDir.boolValue
        let rightExists = fm.fileExists(atPath: rightURL.path, isDirectory: &rightIsDir) && rightIsDir.boolValue

        guard leftExists, rightExists else { return nil }

        return (left: leftURL, right: rightURL)
    }

    private func restoreFromPathsOnly() -> (left: URL, right: URL)? {
        guard let leftPath = defaults.string(forKey: Self.leftKey),
              let rightPath = defaults.string(forKey: Self.rightKey) else {
            return nil
        }

        let leftURL = URL(fileURLWithPath: leftPath)
        let rightURL = URL(fileURLWithPath: rightPath)

        let fm = FileManager.default
        var leftIsDir: ObjCBool = false
        var rightIsDir: ObjCBool = false

        let leftExists = fm.fileExists(atPath: leftURL.path, isDirectory: &leftIsDir) && leftIsDir.boolValue
        let rightExists = fm.fileExists(atPath: rightURL.path, isDirectory: &rightIsDir) && rightIsDir.boolValue

        guard leftExists, rightExists else { return nil }

        return (left: leftURL, right: rightURL)
    }
}
