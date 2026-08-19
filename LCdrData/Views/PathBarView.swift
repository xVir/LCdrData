import AppKit
import SwiftUI

/// Displays the current directory path as clickable breadcrumb segments.
/// Supports editing mode (Cmd+L) for direct path entry.
struct PathBarView: View {

    @Bindable var viewModel: PanelViewModel
    @FocusState private var pathFieldFocused: Bool
    @State private var editedPath: String = ""
    @State private var showCopyConfirmation: Bool = false

    private let pathExpander = TildePathExpander()

    var body: some View {
        HStack(spacing: 2) {
            if viewModel.isPathBarEditing {
                pathTextField
            } else {
                breadcrumbs

                Spacer(minLength: 4)

                copyPathButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
        .onChange(of: viewModel.isPathBarEditing) { _, editing in
            if editing {
                editedPath = viewModel.state.currentDirectory.path
                pathFieldFocused = true
            }
        }
        .onChange(of: pathFieldFocused) { _, focused in
            if !focused {
                viewModel.isPathBarEditing = false
            }
        }
    }

    // MARK: - Breadcrumbs

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(pathComponents, id: \.url) { component in
                    Button {
                        Task {
                            await viewModel.navigate(to: component.url)
                        }
                    } label: {
                        Text(component.name)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    if component.url != viewModel.state.currentDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("pathBar.\(viewModel.side.identifier)")
        .accessibilityValue(viewModel.state.currentDirectory.path)
    }

    // MARK: - Copy Path Button

    private var copyPathButton: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(viewModel.state.currentDirectory.path, forType: .string)

            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyConfirmation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showCopyConfirmation = false
                }
            }
        } label: {
            Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(showCopyConfirmation ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help("Copy path to clipboard")
    }

    // MARK: - Editable Path

    private var pathTextField: some View {
        TextField("Path", text: $editedPath)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .focused($pathFieldFocused)
            .onSubmit {
                let url = pathExpander.expand(editedPath)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                   isDir.boolValue {
                    Task {
                        await viewModel.navigate(to: url)
                    }
                }
                viewModel.isPathBarEditing = false
            }
            .onExitCommand {
                viewModel.isPathBarEditing = false
            }
    }

    // MARK: - Path Components

    private struct PathComponent: Hashable {
        let name: String
        let url: URL
    }

    private var pathComponents: [PathComponent] {
        var components: [PathComponent] = []
        var url = viewModel.state.currentDirectory.standardizedFileURL

        while url.path != "/" {
            components.insert(
                PathComponent(name: url.lastPathComponent, url: url),
                at: 0
            )
            url = url.deletingLastPathComponent()
        }

        // Add root
        components.insert(
            PathComponent(name: "/", url: URL(fileURLWithPath: "/")),
            at: 0
        )

        return components
    }
}
