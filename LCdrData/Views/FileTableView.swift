import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Models
import Utilities
import Formatting
import Services
import ViewModels
import AppEnvironment

/// Displays the file listing as a sortable table with columns for
/// name, size, date modified, and kind.
/// Uses a List with custom column header row for sort control.
package struct FileTableView: View {

    @Bindable var viewModel: PanelViewModel
    package let isActive: Bool
    @Environment(AppState.self) private var appState
    @Environment(\.lcPanelDateFormat) private var panelDateFormat
    @Environment(\.lcPanelFontSize) private var panelFontSize

    /// Drives first responder to the `List` when this panel becomes active so arrow keys move the selection
    /// (Tab switches `focusedPanel` but does not always move keyboard focus off the path bar or column headers).
    @FocusState private var fileListFocused: Bool
    @State private var isFileDropTargeted = false

    package var body: some View {
        VStack(spacing: 0) {
            // Column headers with sort indicators
            columnHeaders

            Divider()

            // File listing
            ScrollViewReader { proxy in
                List(selection: Binding(
                    get: { viewModel.state.cursor.selected },
                    set: { newSelection in
                        // Any user-driven selection on this list (including the
                        // implicit select-under-pointer from a secondary click)
                        // makes this the active panel first, then mutates the
                        // cursor — so the order is activate -> select -> menu.
                        appState.activePanel = viewModel.side
                        viewModel.cursorDidChangeSelection(to: newSelection)
                    }
                )) {
                    ForEach(viewModel.visibleItems) { item in
                        FileRowView(
                            item: item,
                            viewModel: viewModel,
                            dateFormat: panelDateFormat,
                            fontSize: panelFontSize
                        )
                            .tag(item.id)
                            .id(item.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .accessibilityIdentifier("fileRow.\(viewModel.side.identifier).\(item.name)")
                    }
                }
                .accessibilityIdentifier("fileList.\(viewModel.side.identifier)")
                .contextMenu(forSelectionType: UUID.self) { ids in
                    FileContextMenu(
                        model: FileContextMenuModel.resolve(selection: ids, in: viewModel.visibleItems),
                        appState: appState
                    )
                }
                .onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
                    Task {
                        await handleExternalFileDrop(providers: providers, into: viewModel)
                    }
                    return true
                }
                .focused($fileListFocused)
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 24)
                // The Delete key is consumed by the underlying NSTableView before
                // window-level .onKeyPress can see it. Claim the responder-chain
                // delete: action here so it routes to parent navigation instead
                // of NSTableView's default handling.
                .onDeleteCommand {
                    Task { await viewModel.navigateToParent() }
                }
                .onChange(of: viewModel.state.cursor.focused) { _, newID in
                    if let newID {
                        proxy.scrollTo(newID)
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

    private func handleExternalFileDrop(providers: [NSItemProvider], into viewModel: PanelViewModel) async {
        let destinationDirectory = viewModel.state.currentDirectory
        let fm = FileManager.default
        for provider in providers {
            do {
                let object = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                let sourceURL: URL? = {
                    if let url = object as? URL { return url }
                    if let data = object as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    return nil
                }()
                guard let url = sourceURL else { continue }
                let name = url.lastPathComponent
                let dest = destinationDirectory.appendingPathComponent(name)
                if url.standardizedFileURL == dest.standardizedFileURL { continue }
                if fm.fileExists(atPath: dest.path) { continue }
                try fm.copyItem(at: url, to: dest)
            } catch {
                continue
            }
        }
        await viewModel.reload(.keepSelection)
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
    package let title: String
    package let column: FileSortDescriptor.Column
    package let currentSort: FileSortDescriptor
    package let onTap: () async -> Void

    private var isActive: Bool { currentSort.column == column }

    package var body: some View {
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
    package let item: FileItem
    package let viewModel: PanelViewModel
    package let dateFormat: String
    package let fontSize: CGFloat

    @State private var showHighlight: Bool = false

    private var isHighlighted: Bool {
        viewModel.highlightedItemID == item.id
    }

    package var body: some View {
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
            Text(FileFormatter.formatDate(item.modificationDate, format: dateFormat))
                .monospacedDigit()
                .frame(width: 140, alignment: .leading)
                .padding(.leading, 8)

            // Kind column
            Text(FileFormatter.kind(for: item))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 80, alignment: .leading)
        }
        .font(.system(size: fontSize, design: .monospaced))
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
                viewModel.cursorDidChangeSelection(to: [item.id])
            }
        )
        .onDrag {
            guard !item.isParentDirectory else {
                return NSItemProvider()
            }
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
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
        } else if item.isSymlinkToDirectory {
            folderIcon.overlay(alignment: .bottomLeading) { aliasBadge }
        } else if item.isDirectory {
            folderIcon
        } else if item.isSymlink {
            docIcon.overlay(alignment: .bottomLeading) { aliasBadge }
        } else {
            docIcon
        }
    }

    private var folderIcon: some View {
        Image(systemName: "folder.fill")
            .foregroundStyle(.blue)
    }

    private var docIcon: some View {
        Image(systemName: "doc")
            .foregroundStyle(.secondary)
    }

    /// Finder-style alias badge: white-circle background with a small black
    /// up-curving arrow, anchored to the bottom-leading corner of the base icon.
    private var aliasBadge: some View {
        Image(systemName: "arrowshape.turn.up.left.circle.fill")
            .font(.system(size: 9))
            .foregroundStyle(.black, .white)
            .offset(x: -1, y: 1)
    }
}

