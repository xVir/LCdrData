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
    @Environment(AppState.self) private var appState
    @FocusState private var pathFieldFocused: Bool
    @State private var editedPath: String = ""
    @State private var showCopyConfirmation: Bool = false

    private let pathExpander = TildePathExpander()

    private var showHomeAsTilde: Bool {
        appState.configuration.current.panelShowHomeAsTilde
    }

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
                editedPath = displayedPath(for: viewModel.state.location)
                // The text field is only installed once this update commits, so
                // a focus request made here lands on a view that does not exist
                // yet and is dropped. Ask again on the next run loop turn, once
                // the field is in the hierarchy — the same reason
                // `FileTableView` defers its own focus.
                DispatchQueue.main.async {
                    pathFieldFocused = true
                }
            } else {
                pathFieldFocused = false
            }
        }
        .onChange(of: pathFieldFocused) { wasFocused, focused in
            // Only a genuine loss of focus ends editing. The initial false is
            // not a loss, and would otherwise cancel the mode we just entered.
            if wasFocused && !focused {
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
        .accessibilityValue(displayedPath(for: viewModel.state.location))
    }

    // MARK: - Copy Path Button

    private var copyPathButton: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(displayedPath(for: viewModel.state.location), forType: .string)

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
        case .zipArchive(let container, let internalPath),
             .tarGzArchive(let container, let internalPath):
            var components = directoryComponents(through: container.deletingLastPathComponent())
            components.append(
                PathComponent(
                    name: container.lastPathComponent,
                    location: .archive(container: container, internalPath: "")
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
                        location: .archive(container: container, internalPath: accumulatedPath)
                    )
                )
            }
            return components
        }
    }

    private func displayedPath(for location: BrowseLocation) -> String {
        guard showHomeAsTilde else { return location.displayPath }
        return pathExpander.abbreviate(location.displayPath)
    }

    private func directoryComponents(through locationURL: URL) -> [PathComponent] {
        let url = locationURL.standardizedFileURL
        if showHomeAsTilde, let homeRelative = componentsInsideHome(through: url) {
            return homeRelative
        }

        var components: [PathComponent] = []
        var current = url

        while current.path != "/" {
            components.insert(
                PathComponent(name: current.lastPathComponent, location: .directory(current)),
                at: 0
            )
            current = current.deletingLastPathComponent()
        }

        // Add root
        components.insert(
            PathComponent(name: "/", location: .directory(URL(fileURLWithPath: "/"))),
            at: 0
        )

        return components
    }

    /// Breadcrumbs from `~` down to `url`, or `nil` when `url` is outside the home folder.
    private func componentsInsideHome(through url: URL) -> [PathComponent]? {
        let home = pathExpander.homeDirectory.standardizedFileURL
        let homePath = home.path
        guard url.path == homePath || url.path.hasPrefix(homePath + "/") else { return nil }

        var components: [PathComponent] = []
        var current = url
        while current.path != homePath && current.path != "/" {
            components.insert(
                PathComponent(name: current.lastPathComponent, location: .directory(current)),
                at: 0
            )
            current = current.deletingLastPathComponent()
        }
        components.insert(
            PathComponent(name: "~", location: .directory(home)),
            at: 0
        )
        return components
    }
}
