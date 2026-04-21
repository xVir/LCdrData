import SwiftUI

/// Displays the file listing as a sortable table with columns for
/// name, size, date modified, and kind.
/// Uses a List with custom column header row for sort control.
struct FileTableView: View {

    @Bindable var viewModel: PanelViewModel
    let isActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Column headers with sort indicators
            columnHeaders

            Divider()

            // File listing
            ScrollViewReader { proxy in
                List(selection: Binding(
                    get: { viewModel.state.selectedItemIDs },
                    set: { viewModel.state.selectedItemIDs = $0 }
                )) {
                    ForEach(viewModel.state.items) { item in
                        FileRowView(item: item, viewModel: viewModel)
                            .tag(item.id)
                            .id(item.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 24)
                .onDeleteCommand {
                    Task {
                        await viewModel.navigateToParent()
                    }
                }
                .onChange(of: viewModel.state.focusedItemID) { _, newID in
                    if let newID {
                        proxy.scrollTo(newID)
                    }
                }
            }
        }
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            SortableColumnHeader(
                title: "Name",
                column: .name,
                currentSort: viewModel.state.sortDescriptor,
                onTap: { await viewModel.toggleSort(column: .name) }
            )
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            SortableColumnHeader(
                title: "Size",
                column: .size,
                currentSort: viewModel.state.sortDescriptor,
                onTap: { await viewModel.toggleSort(column: .size) }
            )
            .frame(width: 80, alignment: .trailing)

            SortableColumnHeader(
                title: "Date Modified",
                column: .dateModified,
                currentSort: viewModel.state.sortDescriptor,
                onTap: { await viewModel.toggleSort(column: .dateModified) }
            )
            .frame(width: 140, alignment: .leading)

            SortableColumnHeader(
                title: "Kind",
                column: .kind,
                currentSort: viewModel.state.sortDescriptor,
                onTap: { await viewModel.toggleSort(column: .kind) }
            )
            .frame(width: 80, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

// MARK: - Sortable Column Header

private struct SortableColumnHeader: View {
    let title: String
    let column: FileSortDescriptor.Column
    let currentSort: FileSortDescriptor
    let onTap: () async -> Void

    private var isActive: Bool { currentSort.column == column }

    var body: some View {
        Button {
            Task { await onTap() }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(isActive ? .bold : .regular)

                if isActive {
                    Image(systemName: currentSort.ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Row View

private struct FileRowView: View {
    let item: FileItem
    let viewModel: PanelViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Name column
            HStack(spacing: 6) {
                fileIcon
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            // Size column
            Text(sizeText)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)

            // Date Modified column
            Text(FileFormatter.formatDate(item.modificationDate))
                .monospacedDigit()
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 8)

            // Kind column
            Text(FileFormatter.kind(for: item))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 80, alignment: .leading)
        }
        .font(.system(.body, design: .monospaced))
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded {
                Task {
                    if item.isDirectory {
                        await viewModel.navigate(to: item.url)
                    }
                }
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                viewModel.state.selectedItemIDs = [item.id]
            }
        )
    }

    // MARK: - Helpers

    private var sizeText: String {
        if item.isParentDirectory { return "" }
        if item.isDirectory { return "--" }
        return FileFormatter.formatSize(item.size)
    }

    @ViewBuilder
    private var fileIcon: some View {
        if item.isParentDirectory {
            Image(systemName: "arrow.up.doc")
                .foregroundStyle(.secondary)
        } else if item.isSymlink {
            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                .foregroundStyle(.orange)
        } else if item.isDirectory {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
        } else {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        }
    }
}
