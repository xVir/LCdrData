import AppKit
import SwiftUI
import Utilities
import Services
import ViewModels
import AppEnvironment
import Models

/// Displays the current directory path as clickable breadcrumb segments.
/// Supports editing mode (Cmd+L) for direct path entry.
package struct PathBarView: View {

    @Bindable var viewModel: PanelViewModel
    @FocusState private var pathFieldFocused: Bool
    @State private var editedPath: String = ""
    @State private var showCopyConfirmation: Bool = false

    private let pathExpander = TildePathExpander()

    package var body: some View {
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
                editedPath = viewModel.state.location.displayPath
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
                ForEach(pathComponents, id: \.location) { component in
                    Button {
                        Task {
                            await viewModel.navigate(to: component.location)
                        }
                    } label: {
                        Text(component.name)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    if component.location != viewModel.state.location {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("pathBar.\(viewModel.side.identifier)")
        .accessibilityValue(viewModel.state.location.displayPath)
    }

    // MARK: - Copy Path Button

    private var copyPathButton: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(viewModel.state.location.displayPath, forType: .string)

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
        let location: BrowseLocation
    }

    private var pathComponents: [PathComponent] {
        switch viewModel.state.location {
        case .directory(let url):
            return directoryComponents(through: url)
        case .zipArchive(let container, let internalPath):
            var components = directoryComponents(through: container.deletingLastPathComponent())
            components.append(
                PathComponent(
                    name: container.lastPathComponent,
                    location: .zipArchive(container: container, internalPath: "")
                )
            )

            var accumulatedPath = ""
            for segment in internalPath.split(separator: "/") {
                accumulatedPath = accumulatedPath.isEmpty
                    ? String(segment)
                    : accumulatedPath + "/" + segment
                components.append(
                    PathComponent(
                        name: String(segment),
                        location: .zipArchive(container: container, internalPath: accumulatedPath)
                    )
                )
            }
            return components
        }
    }

    private func directoryComponents(through locationURL: URL) -> [PathComponent] {
        var components: [PathComponent] = []
        var url = locationURL.standardizedFileURL

        while url.path != "/" {
            components.insert(
                PathComponent(name: url.lastPathComponent, location: .directory(url)),
                at: 0
            )
            url = url.deletingLastPathComponent()
        }

        // Add root
        components.insert(
            PathComponent(name: "/", location: .directory(URL(fileURLWithPath: "/"))),
            at: 0
        )

        return components
    }
}
