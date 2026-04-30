import Foundation
import KDL
import Observation

enum ConfigurationServiceError: Error, Equatable, Sendable {
    case invalidKDL(String)
    case cannotCreateApplicationSupport
    case cannotWriteUserFile
}

/// Loads bundled default KDL, merges user overrides from Application Support, and applies changes.
@Observable
@MainActor
final class ConfigurationService {

    private(set) var current: AppConfiguration
    private(set) var lastAppliedUserKDL: String = ""

    private let bundle: Bundle
    private let fileManager: FileManager
    private let configDirectory: URL
    private let defaultKDLTextOverride: String?

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.bundle = bundle
        self.fileManager = fileManager
        self.configDirectory = root.appendingPathComponent("com.xvir.LCdrData", isDirectory: true)
        self.defaultKDLTextOverride = nil
        self.current = AppConfiguration.defaults
    }

    /// Test and preview entry point: isolated config directory and optional bundled-default override.
    internal init(
        bundle: Bundle,
        fileManager: FileManager,
        configDirectory: URL,
        defaultKDLTextOverride: String?
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.configDirectory = configDirectory
        self.defaultKDLTextOverride = defaultKDLTextOverride
        self.current = AppConfiguration.defaults
    }

    /// Application Support directory for this app (or test override).
    var applicationSupportDirectory: URL { configDirectory }

    var userConfigFileURL: URL {
        configDirectory.appendingPathComponent("config.kdl", isDirectory: false)
    }

    /// Full default KDL text (bundled resource).
    func defaultKDLText() throws -> String {
        if let defaultKDLTextOverride {
            return defaultKDLTextOverride
        }
        guard let url = bundle.url(forResource: "DefaultConfig", withExtension: "kdl") else {
            throw ConfigurationServiceError.invalidKDL("Missing bundled DefaultConfig.kdl")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Last-applied user overrides read from disk (or empty if none).
    func userKDLText() throws -> String {
        let url = userConfigFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Reads the user file if present, merges with bundled defaults, updates `current` and `lastAppliedUserKDL`.
    func load() throws {
        let defaultsDoc = try Self.parseDocument(try defaultKDLText())
        let base = Self.appConfiguration(from: defaultsDoc, mergingOnto: AppConfiguration.defaults)

        let userText: String
        if fileManager.fileExists(atPath: userConfigFileURL.path) {
            userText = try String(contentsOf: userConfigFileURL, encoding: .utf8)
        } else {
            userText = ""
        }

        if userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current = base
            lastAppliedUserKDL = ""
            return
        }

        let userDoc = try Self.parseDocument(userText)
        current = Self.appConfiguration(from: userDoc, mergingOnto: base)
        lastAppliedUserKDL = userText
    }

    /// Parses user KDL, merges with bundled defaults, validates, writes the user file, updates `current`.
    func apply(fromUserKDL kdlText: String) throws {
        let defaultsDoc = try Self.parseDocument(try defaultKDLText())
        let base = Self.appConfiguration(from: defaultsDoc, mergingOnto: AppConfiguration.defaults)

        let trimmed = kdlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try ensureApplicationSupportExists()
            if fileManager.fileExists(atPath: userConfigFileURL.path) {
                try fileManager.removeItem(at: userConfigFileURL)
            }
            current = base
            lastAppliedUserKDL = ""
            return
        }

        let userDoc = try Self.parseDocument(kdlText)
        let merged = Self.appConfiguration(from: userDoc, mergingOnto: base)

        try ensureApplicationSupportExists()
        guard let data = kdlText.data(using: .utf8) else {
            throw ConfigurationServiceError.cannotWriteUserFile
        }
        do {
            try data.write(to: userConfigFileURL, options: .atomic)
        } catch {
            throw ConfigurationServiceError.cannotWriteUserFile
        }

        current = merged
        lastAppliedUserKDL = kdlText
    }

    private func ensureApplicationSupportExists() throws {
        let dir = applicationSupportDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw ConfigurationServiceError.cannotCreateApplicationSupport
            }
        }
    }

    // MARK: - KDL parsing

    private static func parseDocument(_ text: String) throws -> KDLDocument {
        do {
            return try KDL.parseDocument(text)
        } catch {
            throw ConfigurationServiceError.invalidKDL(error.localizedDescription)
        }
    }

    /// Applies all recognized nodes in `document` onto `mergingOnto` (typically bundled defaults, then user file).
    static func appConfiguration(from document: KDLDocument, mergingOnto base: AppConfiguration) -> AppConfiguration {
        var result = base

        if let panel = document["panel"] {
            if let hidden = boolArg(from: panel, childName: "show-hidden-files") {
                result.panelShowHiddenFiles = hidden
            }
            if let col = stringArg(from: panel, childName: "sort-by").flatMap(Self.parseSortColumn) {
                result.panelSortColumn = col
            }
            if let asc = boolArg(from: panel, childName: "sort-ascending") {
                result.panelSortAscending = asc
            }
        }

        if let appearance = document["appearance"] {
            if let size = intArg(from: appearance, childName: "font-size"), size > 6, size < 72 {
                result.appearanceFontSize = Double(size)
            }
            if let fmt = stringArg(from: appearance, childName: "date-format") {
                result.appearanceDateFormat = fmt
            }
        }

        if let bookmarks = document["bookmarks"],
           let entries = bookmarkEntries(from: bookmarks) {
            result.bookmarkEntries = entries
        } else if document["bookmarks"] != nil {
            result.bookmarkEntries = []
        }

        if let editor = document["editor"],
           let bundleID = stringArg(from: editor, childName: "default-app") {
            result.editorDefaultAppBundleID = bundleID
        }

        return result
    }

    private static func boolArg(from node: KDLNode, childName: String) -> Bool? {
        guard let child = node.child(childName), let v = child.arg else { return nil }
        if case .bool(let b, _, _) = v { return b }
        return nil
    }

    private static func stringArg(from node: KDLNode, childName: String) -> String? {
        guard let child = node.child(childName), let v = child.arg else { return nil }
        if case .string(let s, _, _) = v { return s }
        return nil
    }

    private static func intArg(from node: KDLNode, childName: String) -> Int? {
        guard let child = node.child(childName), let v = child.arg else { return nil }
        if case .int(let i, _, _) = v { return i }
        return nil
    }

    private static func bookmarkEntries(from bookmarksNode: KDLNode) -> [AppConfiguration.BookmarkEntry]? {
        let dash = bookmarksNode.dashVals
        guard !dash.isEmpty else { return nil }
        var out: [AppConfiguration.BookmarkEntry] = []
        for entry in dash {
            guard let v = entry else { continue }
            guard let raw = string(from: v) else { continue }
            let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let label = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let path = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !path.isEmpty else { continue }
            out.append(AppConfiguration.BookmarkEntry(label: label, path: path))
        }
        return out.isEmpty ? [] : out
    }

    private static func string(from value: KDLValue) -> String? {
        if case .string(let s, _, _) = value { return s }
        return nil
    }

    private static func parseSortColumn(_ raw: String) -> FileSortDescriptor.Column? {
        let n = raw.lowercased().replacingOccurrences(of: "-", with: "")
        switch n {
        case "name": return .name
        case "size": return .size
        case "datemodified": return .dateModified
        case "datecreated": return .dateCreated
        case "kind": return .kind
        default: return nil
        }
    }
}
