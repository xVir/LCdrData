import SwiftUI

/// Per-panel status bar showing item count, selection count, and total size.
struct StatusBarView: View {

    let viewModel: PanelViewModel

    var body: some View {
        HStack {
            Text(itemCountText)
            Spacer()
            if !selectionText.isEmpty {
                Text(selectionText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Computed Text

    private var itemCountText: String {
        let count = viewModel.state.items.filter { !$0.isParentDirectory }.count
        let dirs = viewModel.state.items.filter { $0.isDirectory && !$0.isParentDirectory }.count
        let files = count - dirs
        return "\(files) file\(files == 1 ? "" : "s"), \(dirs) folder\(dirs == 1 ? "" : "s")"
    }

    private var selectionText: String {
        let selectedCount = viewModel.state.cursor.selected.count
        guard selectedCount > 0 else { return "" }

        let selectedItems = viewModel.state.items.filter {
            viewModel.state.cursor.selected.contains($0.id)
        }
        let totalSize = selectedItems.compactMap(\.size).reduce(0, +)

        return "\(selectedCount) selected (\(FileFormatter.formatSize(totalSize)))"
    }
}
