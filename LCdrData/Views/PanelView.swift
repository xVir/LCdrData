import SwiftUI

/// A single file panel containing a path bar, file table, and status bar.
/// Visually indicates whether it is the active (focused) panel.
struct PanelView: View {

    @Bindable var viewModel: PanelViewModel
    @Environment(AppState.self) private var appState

    private var isActive: Bool {
        appState.activePanel == viewModel.side
    }

    var body: some View {
        VStack(spacing: 0) {
            PathBarView(viewModel: viewModel)

            Divider()

            if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                FileTableView(viewModel: viewModel, isActive: isActive)
                    .overlay {
                        if viewModel.isLoading {
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

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            if viewModel.isPermissionError {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Access Denied")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Grant Access\u{2026}") {
                    Task {
                        await viewModel.requestAccessAndReload()
                    }
                }
                .buttonStyle(.borderedProminent)
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
                        await viewModel.loadDirectory()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .focusable()
    }
}
