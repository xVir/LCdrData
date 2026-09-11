import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Services
import ViewModels
import AppEnvironment
import Models

/// A single file panel containing a path bar, file table, and status bar.
/// Visually indicates whether it is the active (focused) panel.
package struct PanelView: View {

    @Bindable var viewModel: PanelViewModel
    @Environment(AppState.self) private var appState

    private var isActive: Bool {
        appState.activePanel == viewModel.side
    }

    package var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.isTabBarVisible {
                tabBar
                    .frame(height: 30)
                    .padding(.horizontal, 8)
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
            }

            PathBarView(viewModel: viewModel)

            Divider()

            if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                FileTableView(
                    viewModel: viewModel,
                    isActive: isActive
                )
                    .overlay {
                        // Only show the spinner on a genuinely empty load — for
                        // reloads where existing rows are still visible, let
                        // SwiftUI swap them in place to avoid a blink.
                        if viewModel.isLoading && viewModel.state.items.isEmpty {
                            ProgressView("Loading...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.background.opacity(0.6))
                        }
                    }
            }

            Divider()

            StatusBarView(viewModel: viewModel)
        }
        .background(isActive ? Color.accentColor.opacity(0.03) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                if !isActive {
                    appState.activePanel = viewModel.side
                }
            }
        )
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.state.tabs.enumerated()), id: \.element.id) { index, tab in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 18)
                    }

                    TabBarItemView(
                        viewModel: viewModel,
                        appState: appState,
                        index: index,
                        tab: tab
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private struct TabBarItemView: View {
        let viewModel: PanelViewModel
        let appState: AppState
        let index: Int
        let tab: PanelTab

        @State private var isHovered = false

        var body: some View {
            ZStack(alignment: .leading) {
                Button {
                    Task { await viewModel.activateTab(at: index) }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: index == viewModel.state.activeTabIndex ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(minWidth: 110, maxWidth: 160)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == viewModel.state.activeTabIndex ? .primary : .secondary)
                .frame(height: 24)
                .background(
                    index == viewModel.state.activeTabIndex
                        ? Color.accentColor.opacity(0.18)
                        : isHovered
                            ? Color.primary.opacity(0.08)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .contentShape(Rectangle())
                .onDrag {
                    let provider = NSItemProvider(object: "\(viewModel.side.identifier):\(index)" as NSString)
                    provider.suggestedName = tab.title
                    return provider
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    provider.loadObject(ofClass: NSString.self) { item, _ in
                        guard let value = item as? String else { return }
                        let payload = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                        guard payload.count == 2,
                              let sourceSide = payload.first,
                              let sourceIndex = Int(payload[1]) else { return }

                        let sourceSideID = String(sourceSide)
                        let fromSide: PanelSide = sourceSideID == PanelSide.left.identifier ? .left : .right
                        if fromSide.identifier == viewModel.side.identifier {
                            Task { @MainActor in
                                viewModel.moveTab(from: sourceIndex, to: index)
                            }
                        } else {
                            let sourcePanel = fromSide.identifier == PanelSide.left.identifier ? appState.leftPanel : appState.rightPanel
                            let movedTab = sourcePanel.state.tabs[sourceIndex]
                            sourcePanel.state.tabs.remove(at: sourceIndex)
                            if sourcePanel.state.activeTabIndex >= sourceIndex {
                                sourcePanel.state.activeTabIndex = max(0, sourcePanel.state.activeTabIndex - 1)
                            }
                            if sourcePanel.state.tabs.isEmpty {
                                sourcePanel.state.tabs = [PanelTab(location: sourcePanel.state.location)]
                                sourcePanel.state.activeTabIndex = 0
                            }
                            if let active = sourcePanel.state.activeTab {
                                sourcePanel.state.location = active.location
                                sourcePanel.state.cursor = active.cursor
                                sourcePanel.state.sortDescriptor = active.sortDescriptor
                                sourcePanel.state.showHiddenFiles = active.showHiddenFiles
                                sourcePanel.state.items = active.items ?? sourcePanel.state.items
                            }

                            let destinationIndex = min(index, viewModel.state.tabs.count)
                            viewModel.state.tabs.insert(movedTab, at: destinationIndex)
                            viewModel.state.activeTabIndex = destinationIndex
                            if let active = viewModel.state.activeTab {
                                viewModel.state.location = active.location
                                viewModel.state.cursor = active.cursor
                                viewModel.state.sortDescriptor = active.sortDescriptor
                                viewModel.state.showHiddenFiles = active.showHiddenFiles
                                viewModel.state.items = active.items ?? viewModel.state.items
                            }
                            Task { @MainActor in
                                await viewModel.activateTab(at: destinationIndex)
                            }
                        }
                    }
                    return true
                }
                .contextMenu {
                    Button("New Tab") {
                        Task { await viewModel.createTab(from: index) }
                    }
                    Button("Close Tab") {
                        Task { await viewModel.closeTab(at: index) }
                    }
                    Button("Close Other Tabs") {
                        Task { await viewModel.closeOtherTabs(excluding: index) }
                    }
                    Button("Close Tabs to the Right") {
                        Task { await viewModel.closeTabsToRight(from: index) }
                    }
                    Button("Copy Path") {
                        viewModel.copyTabPath(at: index)
                    }
                }

                if viewModel.state.tabs.count > 1 {
                    Button {
                        Task { await viewModel.closeTab(at: index) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: isHovered ? 14 : 0, height: 14)
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                    .zIndex(2)
                }
            }
            .frame(height: 26)
            .padding(2)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                Task { await viewModel.activateTab(at: index) }
            }
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            if viewModel.isPermissionError {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("No access to this folder")
                    .font(.headline)
                Text("Press \u{2318}L to navigate elsewhere, or grant access via "
                     + "LCdrData → Grant Folder Access\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Failed to load directory")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task {
                        await viewModel.reload(.fresh)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .focusable()
    }
}
