import SwiftUI
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
                    HStack(spacing: 6) {
                        Button {
                            Task { await viewModel.activateTab(at: index) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                Text(tab.title)
                                    .font(.system(size: 12, weight: index == viewModel.state.activeTabIndex ? .semibold : .regular))
                                    .lineLimit(1)
                                    .frame(maxWidth: 150)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == viewModel.state.activeTabIndex ? .primary : .secondary)
                        .frame(height: 24)
                        .background(
                            index == viewModel.state.activeTabIndex
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        if viewModel.state.tabs.count > 1 {
                            Button {
                                Task { await viewModel.closeTab(at: index) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                        }
                    }
                    .padding(2)
                    .frame(height: 26)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
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
