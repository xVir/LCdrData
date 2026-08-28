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

    @Environment(PanelColumnLayoutModel.self) private var columnLayouts

    /// The width the columns have to share, measured once for the whole table so
    /// the headers and the rows can never disagree about it.
    @State private var contentWidth: CGFloat = 0

    /// The layout as it stood when the current drag began. `translation` is
    /// cumulative, so it has to be applied to a fixed starting point — applying
    /// it to the live layout every frame compounds and the column runs away.
    @State private var dragBaseline: PanelColumnLayout?

    /// The header being dragged to a new position, and how far it has travelled.
    @State private var reorder: (column: FileColumn, index: Int, translation: CGFloat)?

    private var layout: PanelColumnLayout { columnLayouts.layout(for: viewModel.side) }

    /// The header row's own coordinate space. Both drags measure their
    /// translation against it rather than against the view being dragged: a
    /// resize handle rides the edge it is moving and a dragged header is
    /// re-slotted mid-gesture, so a local translation is measured from a moving
    /// origin and the column stutters or runs away.
    private var headerSpace: NamedCoordinateSpace {
        .named("columnHeaders.\(viewModel.side.identifier)")
    }

    /// What to draw: during a reorder the headers preview the pending order,
    /// while the rows keep the committed one — re-animating hundreds of list
    /// rows on every index crossing is not worth the fidelity.
    private var previewLayout: PanelColumnLayout {
        guard let reorder, let target = reorderTarget else { return layout }
        return layout.moving(from: reorder.index, to: target)
    }

    /// The index the header being dragged would land on if released now.
    private var reorderTarget: Int? {
        guard let reorder else { return nil }
        return layout.targetIndex(
            draggedIndex: reorder.index,
            translationX: Double(reorder.translation),
            widths: layout.resolvedWidths(availableWidth: Double(contentWidth))
        )
    }

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
                            columns: layout.columns,
                            widths: layout.resolvedWidths(availableWidth: Double(contentWidth)),
                            dateFormat: panelDateFormat,
                            fontSize: panelFontSize
                        )
                            .tag(item.id)
                            .id(item.id)
                            .listRowInsets(EdgeInsets(
                                top: 2,
                                leading: FileColumnMetrics.horizontalInset,
                                bottom: 2,
                                trailing: FileColumnMetrics.horizontalInset
                            ))
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
        // The measurement must be taken on a frame that is sized by the panel
        // and not by what is in it. Measuring the VStack directly closed a loop
        // — the rows are as wide as `contentWidth` makes them, so any width the
        // table once reported it kept reporting, and a resize drag chased its
        // own tail instead of tracking the pointer.
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            // onGeometryChange rather than a wrapping GeometryReader, which
            // would change the layout of everything inside it.
            contentWidth = max(0, width - FileColumnMetrics.horizontalInset * 2)
        }
    }

    private func focusFileListIfAppropriate() {
        guard !viewModel.isPathBarEditing else { return }
        DispatchQueue.main.async {
            fileListFocused = true
        }
    }

    private func handleExternalFileDrop(providers: [NSItemProvider], into viewModel: PanelViewModel) async {
        var sourceURLs: [URL] = []
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
                sourceURLs.append(url)
            } catch {
                continue
            }
        }
        await appState.fileOperations.performDrop(
            urls: sourceURLs,
            to: viewModel.state.location
        )
        await viewModel.reload(.keepSelection)
        await appState.inactivePanelViewModel.reload(.keepSelection)
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        let widths = previewLayout.resolvedWidths(availableWidth: Double(contentWidth))
        return HStack(spacing: 0) {
            ForEach(Array(previewLayout.columns.enumerated()), id: \.element) { index, column in
                let isDragged = reorder?.column == column
                SortableColumnHeader(
                    column: column,
                    currentSort: viewModel.state.sortDescriptor,
                    coordinateSpace: headerSpace,
                    onSort: { await viewModel.toggleSort(column: column.sortColumn) },
                    onDragChanged: { translation in
                        // The dragged header's own index must come from the
                        // committed order, not the preview, or the target would
                        // be computed against a moving reference.
                        guard let home = layout.columns.firstIndex(of: column) else { return }
                        reorder = (column: column, index: home, translation: translation)
                    },
                    onDragEnded: { commitReorder() }
                )
                .frame(width: CGFloat(widths[index]), alignment: column.alignment)
                .opacity(isDragged ? 0.6 : 1)
                .zIndex(isDragged ? 2 : 0)
                .overlay(alignment: .trailing) {
                    if index < previewLayout.columns.count - 1 {
                        columnResizeHandle(after: column)
                    }
                }
                // The displaced headers slide to their new slots; the dragged
                // one is pinned to the pointer instead, so animating it would
                // make it lag the cursor by the animation's duration.
                .animation(isDragged ? nil : .easeInOut(duration: 0.15), value: previewLayout.columns)
                .offset(x: isDragged ? dragOffset(previewIndex: index, previewWidths: widths) : 0)
            }
        }
        .padding(.horizontal, FileColumnMetrics.horizontalInset)
        .padding(.vertical, 4)
        .background(.bar)
        .coordinateSpace(headerSpace)
    }

    /// How far the dragged header has to move from the slot the preview put it
    /// in to sit under the pointer. The pointer position is derived from the
    /// committed layout, which does not move mid-drag, and clamped to the
    /// table so a header can never be dragged out of its own panel.
    private func dragOffset(previewIndex: Int, previewWidths: [Double]) -> CGFloat {
        guard let reorder else { return 0 }
        let committed = layout.resolvedWidths(availableWidth: Double(contentWidth))
        guard committed.indices.contains(reorder.index) else { return 0 }
        let homeX = committed.prefix(reorder.index).reduce(0, +)
        let limit = max(0, Double(contentWidth) - committed[reorder.index])
        let pointerX = min(max(0, homeX + Double(reorder.translation)), limit)
        let previewX = previewWidths.prefix(previewIndex).reduce(0, +)
        return CGFloat(pointerX - previewX)
    }

    /// The grab area between two headers. A sibling of the header rather than a
    /// child of it, so a drag here can never reach the sort gesture underneath.
    private func columnResizeHandle(after column: FileColumn) -> some View {
        ColumnResizeHandle(
            coordinateSpace: headerSpace,
            onChanged: { translation in
                guard let index = layout.columns.firstIndex(of: column) else { return }
                let base = dragBaseline ?? layout
                dragBaseline = base
                columnLayouts.setLayout(
                    base.resizing(
                        dividerAfter: index,
                        by: Double(translation),
                        availableWidth: Double(contentWidth)
                    ),
                    for: viewModel.side
                )
            },
            onEnded: {
                dragBaseline = nil
                columnLayouts.commit()
            }
        )
        .offset(x: FileColumnMetrics.resizeHandleWidth / 2)
        .zIndex(1)
        .accessibilityIdentifier("columnDivider.\(viewModel.side.identifier).\(column.rawValue)")
    }

    private func commitReorder() {
        defer { reorder = nil }
        guard let reorder, let target = reorderTarget, target != reorder.index else { return }
        columnLayouts.setLayout(layout.moving(from: reorder.index, to: target), for: viewModel.side)
        columnLayouts.commit()
    }
}

// MARK: - Column Geometry

package enum FileColumnMetrics {
    /// The inset the header and the list rows share. One constant, because the
    /// two drifting apart is exactly how the columns stopped lining up before.
    package static let horizontalInset: CGFloat = 8
    package static let resizeHandleWidth: CGFloat = 10
    /// Breathing room between a cell's text and the column's edges. Without it
    /// a trailing-aligned column and the leading-aligned one after it run their
    /// text together — "SizeDate Modified".
    package static let cellPadding: CGFloat = 4
}

extension FileColumn {
    var title: String {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .dateModified: "Date Modified"
        case .kind: "Kind"
        }
    }

    var sortColumn: FileSortDescriptor.Column {
        switch self {
        case .name: .name
        case .size: .size
        case .dateModified: .dateModified
        case .kind: .kind
        }
    }

    var alignment: Alignment {
        self == .size ? .trailing : .leading
    }
}

// MARK: - Resize Handle

private struct ColumnResizeHandle: View {
    let coordinateSpace: NamedCoordinateSpace
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    @State private var isHovering = false

    var body: some View {
        Color.clear
            .frame(width: FileColumnMetrics.resizeHandleWidth)
            .contentShape(Rectangle())
            .onHover { inside in
                // push/pop must balance: without the flag a missed exit — the
                // pointer leaving the window fast — leaks a pushed cursor.
                guard inside != isHovering else { return }
                isHovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: coordinateSpace)
                    .onChanged { onChanged($0.translation.width) }
                    .onEnded { _ in onEnded() }
            )
    }
}

// MARK: - Sortable Column Header

private struct SortableColumnHeader: View {
    package let column: FileColumn
    package let currentSort: FileSortDescriptor
    package let coordinateSpace: NamedCoordinateSpace
    package let onSort: () async -> Void
    package let onDragChanged: (CGFloat) -> Void
    package let onDragEnded: () -> Void

    private var isActive: Bool { currentSort.column == column.sortColumn }

    package var body: some View {
        HStack(spacing: 4) {
            Text(column.title)
                .font(.caption)
                .fontWeight(isActive ? .bold : .regular)

            if isActive {
                Image(systemName: currentSort.ascending ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, FileColumnMetrics.cellPadding)
        .frame(maxWidth: .infinity, alignment: column.alignment)
        .contentShape(Rectangle())
        // One gesture for both jobs: the drag takes priority but only starts
        // after 4pt of travel, so releasing before that lets the tap sort. A
        // Button's own press handling does not compose with .exclusively,
        // which is why this is a plain label with accessibility added back.
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: coordinateSpace)
                .onChanged { onDragChanged($0.translation.width) }
                .onEnded { _ in onDragEnded() }
                .exclusively(
                    before: TapGesture().onEnded {
                        Task { await onSort() }
                    }
                )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(column.title)
        .accessibilityAction { Task { await onSort() } }
        .accessibilityIdentifier("columnHeader.\(column.rawValue)")
    }
}

// MARK: - File Row View

private struct FileRowView: View {
    package let item: FileItem
    package let viewModel: PanelViewModel
    /// The order and widths the header is drawing right now, handed down as a
    /// plain value so a row can never compute its own geometry.
    package let columns: [FileColumn]
    package let widths: [Double]
    package let dateFormat: String
    package let fontSize: CGFloat

    @State private var showHighlight: Bool = false

    private var isHighlighted: Bool {
        viewModel.highlightedItemID == item.id
    }

    package var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element) { index, column in
                cell(for: column)
                    .padding(.horizontal, FileColumnMetrics.cellPadding)
                    .frame(
                        width: index < widths.count ? CGFloat(widths[index]) : 0,
                        alignment: column.alignment
                    )
                    .clipped()
            }
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
            if item.archiveContainer != nil {
                let provider = NSItemProvider()
                provider.suggestedName = item.name
                provider.registerFileRepresentation(
                    forTypeIdentifier: UTType.data.identifier,
                    fileOptions: [],
                    visibility: .all
                ) { completion in
                    Task { @MainActor in
                        let url = await viewModel.preparedFileURL(for: item)
                        completion(url, false, nil)
                    }
                    return nil
                }
                return provider
            }
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func cell(for column: FileColumn) -> some View {
        switch column {
        case .name:
            HStack(spacing: 6) {
                fileIcon
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        case .size:
            Text(sizeText)
                .monospacedDigit()
                .lineLimit(1)
        case .dateModified:
            // Without a line limit a column dragged down to its minimum wraps
            // the date onto a second line and the row grows taller than its
            // neighbours; truncating keeps every row the same height.
            Text(FileFormatter.formatDate(item.modificationDate, format: dateFormat))
                .monospacedDigit()
                .lineLimit(1)
        case .kind:
            Text(FileFormatter.kind(for: item))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

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

