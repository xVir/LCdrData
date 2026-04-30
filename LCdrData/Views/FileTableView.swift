import SwiftUI

/// Displays the file listing as a sortable table with columns for
/// name, size, date modified, and kind.
/// Uses a List with custom column header row for sort control.
struct FileTableView: View {

    @Bindable var viewModel: PanelViewModel
    let isActive: Bool
    /// When set (typically for the active panel), the standard Delete menu / command moves selection to Trash.
    var onDeleteSelection: (() -> Void)? = nil

    /// Drives first responder to the `List` when this panel becomes active so arrow keys move the selection
    /// (Tab switches `focusedPanel` but does not always move keyboard focus off the path bar or column headers).
    @FocusState private var fileListFocused: Bool

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
                    ForEach(viewModel.visibleItems) { item in
                        FileRowView(item: item, viewModel: viewModel)
                            .tag(item.id)
                            .id(item.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                }
                .focused($fileListFocused)
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 24)
                .modifier(ListDeleteCommandModifier(onDelete: onDeleteSelection))
                .onChange(of: viewModel.state.focusedItemID) { _, newID in
                    if let newID {
                        proxy.scrollTo(newID)
                    }
                }
                // Track the user's cursor position: when arrow-key navigation
                // or a click changes the selection to a single item, update
                // focusedItemID so it always reflects the current position.
                // When clicking empty space clears the selection, restore it
                // from focusedItemID so the cursor never disappears.
                .onChange(of: viewModel.state.selectedItemIDs) { _, newValue in
                    if newValue.isEmpty {
                        if let focusedID = viewModel.state.focusedItemID {
                            viewModel.state.selectedItemIDs = [focusedID]
                        }
                    } else if newValue.count == 1 {
                        viewModel.state.focusedItemID = newValue.first
                    }
                }
                .onChange(of: isActive) { _, active in
                    if active {
                        focusFileListIfAppropriate()
                    } else {
                        fileListFocused = false
                    }
                }
                .onChange(of: viewModel.isPathBarEditing) { _, editing in
                    if editing {
                        fileListFocused = false
                    } else if isActive {
                        focusFileListIfAppropriate()
                    }
                }
            }
        }
    }

    private func focusFileListIfAppropriate() {
        guard !viewModel.isPathBarEditing else { return }
        DispatchQueue.main.async {
            fileListFocused = true
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

    @State private var showHighlight: Bool = false

    private var isHighlighted: Bool {
        viewModel.highlightedItemID == item.id
    }

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
        .listRowBackground(
            showHighlight
                ? Color.green.opacity(0.25)
                : Color.clear
        )
        .onChange(of: isHighlighted) { _, highlighted in
            if highlighted {
                showHighlight = true
                withAnimation(.easeOut(duration: 1.2)) {
                    showHighlight = false
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded {
                Task {
                    await viewModel.openItem(item)
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

// MARK: - Delete command

/// Wires the Edit > Delete menu to Trash for the active panel’s list.
private struct ListDeleteCommandModifier: ViewModifier {
    let onDelete: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDelete {
            content.onDeleteCommand(perform: onDelete)
        } else {
            content
        }
    }
}
