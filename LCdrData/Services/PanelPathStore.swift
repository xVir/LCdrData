import Foundation

/// Persists and restores the last-used directory paths for both panels.
protocol PanelPathStoreProtocol: Sendable {
    func save(leftPath: String, rightPath: String)
    func restore() -> (left: URL, right: URL)?
}

/// Stores panel paths in UserDefaults.
final class PanelPathStore: PanelPathStoreProtocol, Sendable {

    private static let leftKey = "panelPath.left"
    private static let rightKey = "panelPath.right"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(leftPath: String, rightPath: String) {
        defaults.set(leftPath, forKey: Self.leftKey)
        defaults.set(rightPath, forKey: Self.rightKey)
    }

    func restore() -> (left: URL, right: URL)? {
        guard let leftPath = defaults.string(forKey: Self.leftKey),
              let rightPath = defaults.string(forKey: Self.rightKey) else {
            return nil
        }

        let leftURL = URL(fileURLWithPath: leftPath)
        let rightURL = URL(fileURLWithPath: rightPath)

        let fm = FileManager.default
        var isDir: ObjCBool = false

        let leftExists = fm.fileExists(atPath: leftURL.path, isDirectory: &isDir) && isDir.boolValue
        let rightExists = fm.fileExists(atPath: rightURL.path, isDirectory: &isDir) && isDir.boolValue

        // Only restore if both paths still exist as directories.
        // If one is gone, fall back to defaults for both (caller handles nil).
        guard leftExists, rightExists else { return nil }

        return (left: leftURL, right: rightURL)
    }
}
