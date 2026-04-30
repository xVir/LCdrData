import SwiftUI

/// Sidebar listing configured favorite folders (`bookmarks` in KDL); opens in the active panel.
struct BookmarksSidebarView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Favorites") {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Button {
                        Task {
                            let url = Self.expandedDirectoryURL(path: entry.path)
                            await appState.activePanelViewModel.navigate(to: url)
                        }
                    } label: {
                        Label(entry.label, systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var entries: [AppConfiguration.BookmarkEntry] {
        appState.configuration.current.bookmarkEntries
    }

    private static func expandedDirectoryURL(path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
}
