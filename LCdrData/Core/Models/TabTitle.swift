import Foundation

/// The name shown on a panel tab. Directories that share a leaf name pick up
/// ancestor names until the titles in the window differ. An archive title
/// always includes the archive file name and the path inside it.
package nonisolated struct TabTitle: Equatable, Sendable {
    package let components: [String]
    /// Index of the archive file name in `components`, when this titles an archive location.
    package let archiveIndex: Int?

    package var text: String {
        components.joined(separator: "/")
    }

    package static func labels(for locations: [BrowseLocation]) -> [TabTitle] {
        var entries = locations.map(entry(for:))
        distinguish(&entries)
        return entries.map(title(of:))
    }

    /// Drops middle path components until every title satisfies `fits`.
    /// Different locations keep titles that still differ.
    package static func fitted(_ titles: [TabTitle], fits: (String) -> Bool) -> [String] {
        var visible = titles.map { Array($0.components.indices) }
        while true {
            let rendered = zip(titles, visible).map { render($0, visible: $1) }
            guard let index = rendered.indices.first(where: { !fits(rendered[$0]) }) else {
                return rendered
            }
            guard let next = dropOne(
                from: titles[index],
                visible: visible[index],
                titleIndex: index,
                titles: titles
            ) else {
                return rendered
            }
            visible[index] = next
        }
    }

    private struct Entry {
        var components: [String]
        var identity: String
        var suffixLength: Int
        var archiveIndex: Int?
    }

    private static func entry(for location: BrowseLocation) -> Entry {
        switch location {
        case .directory(let url):
            let path = standardizedPath(url)
            return Entry(
                components: components(of: path),
                identity: "dir:\(path)",
                suffixLength: 1,
                archiveIndex: nil
            )
        case .zipArchive(let container, let internalPath),
             .tarGzArchive(let container, let internalPath):
            let containerPath = standardizedPath(container)
            let outside = components(of: parentPath(of: containerPath))
            let inside = internalPath.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            let archiveName = (containerPath as NSString).lastPathComponent
            let format = ArchiveFormat(url: container) == .tarGz ? "tar" : "zip"
            return Entry(
                components: outside + [archiveName] + inside,
                identity: "\(format):\(containerPath)\n\(internalPath)",
                suffixLength: 1 + inside.count,
                archiveIndex: outside.count
            )
        }
    }

    private static func distinguish(_ entries: inout [Entry]) {
        while true {
            let titles = entries.map { title(of: $0).text }
            var grow = Set<Int>()
            for left in entries.indices {
                for right in entries.indices where left < right {
                    guard entries[left].identity != entries[right].identity else { continue }
                    if titles[left] == titles[right] {
                        grow.insert(left)
                        grow.insert(right)
                    } else if entries[left].suffixLength == 1,
                              entries[right].suffixLength == 1,
                              titles[left].caseInsensitiveCompare(titles[right]) == .orderedSame {
                        grow.insert(left)
                        grow.insert(right)
                    }
                }
            }
            guard !grow.isEmpty else { return }

            var didGrow = false
            for index in grow where entries[index].suffixLength < entries[index].components.count {
                entries[index].suffixLength += 1
                didGrow = true
            }
            guard didGrow else { return }
        }
    }

    private static func title(of entry: Entry) -> TabTitle {
        guard !entry.components.isEmpty else {
            return TabTitle(components: ["/"], archiveIndex: nil)
        }
        let length = min(entry.suffixLength, entry.components.count)
        let start = entry.components.count - length
        let shown = Array(entry.components[start...])
        let archiveIndex = entry.archiveIndex.map { $0 - start }
        return TabTitle(components: shown, archiveIndex: archiveIndex)
    }

    private static func dropOne(
        from title: TabTitle,
        visible: [Int],
        titleIndex: Int,
        titles: [TabTitle]
    ) -> [Int]? {
        let pins = pinnedIndices(of: title)
        let parent = parentIndex(of: title)
        let droppable = visible.filter { !pins.contains($0) }
        let shared = droppable.filter { !isDistinguishing($0, titleIndex: titleIndex, titles: titles) }
        let sharedMiddles = shared.filter { $0 != parent }
        let sharedParent = shared.filter { $0 == parent }
        let distinguishing = droppable.filter { isDistinguishing($0, titleIndex: titleIndex, titles: titles) }
        for index in sharedMiddles + sharedParent + distinguishing {
            let next = visible.filter { $0 != index }
            if retainsADifference(next, titleIndex: titleIndex, titles: titles) {
                return next
            }
        }
        return nil
    }

    private static func isDistinguishing(_ index: Int, titleIndex: Int, titles: [TabTitle]) -> Bool {
        let mine = titles[titleIndex].components
        guard mine.indices.contains(index) else { return false }
        for other in titles.indices where titles[other].components != mine {
            let theirs = titles[other].components
            if !theirs.indices.contains(index) || theirs[index] != mine[index] {
                return true
            }
        }
        return false
    }

    /// True when every other location still differs in some component this title keeps.
    private static func retainsADifference(_ visible: [Int], titleIndex: Int, titles: [TabTitle]) -> Bool {
        let mine = titles[titleIndex].components
        for other in titles.indices where titles[other].components != mine {
            let theirs = titles[other].components
            let differs = visible.contains { index in
                !theirs.indices.contains(index) || theirs[index] != mine[index]
            }
            if !differs { return false }
        }
        return true
    }

    private static func pinnedIndices(of title: TabTitle) -> Set<Int> {
        guard let last = title.components.indices.last else { return [] }
        var pins: Set<Int> = [last]
        if let archiveIndex = title.archiveIndex {
            pins.insert(archiveIndex)
        } else if let first = title.components.indices.first {
            pins.insert(first)
        }
        return pins
    }

    private static func parentIndex(of title: TabTitle) -> Int? {
        guard title.components.count >= 2 else { return nil }
        let parent = title.components.count - 2
        if title.archiveIndex == nil, parent == 0 { return nil }
        if parent == title.archiveIndex { return nil }
        return parent
    }

    private static func render(_ title: TabTitle, visible: [Int]) -> String {
        let indices = visible.sorted()
        guard let first = indices.first else { return title.text }
        var parts = [title.components[first]]
        var previous = first
        for index in indices.dropFirst() {
            if index > previous + 1 {
                parts.append("…")
            }
            parts.append(title.components[index])
            previous = index
        }
        return parts.joined(separator: "/")
    }

    private static func standardizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func parentPath(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "/" : parent
    }
}
