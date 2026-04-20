//
//  PathBarView.swift
//  LCDR Data
//
//  Created by Dima Skachkov on 02.04.2026.
//

import SwiftUI

/// Displays the current directory path as clickable breadcrumb segments.
/// Supports editing mode (Cmd+L) for direct path entry.
struct PathBarView: View {

    @Bindable var viewModel: PanelViewModel
    @State private var isEditing: Bool = false
    @State private var editedPath: String = ""

    var body: some View {
        HStack(spacing: 2) {
            if isEditing {
                pathTextField
            } else {
                breadcrumbs
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
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
    }

    // MARK: - Editable Path

    private var pathTextField: some View {
        TextField("Path", text: $editedPath)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .onSubmit {
                let url = URL(fileURLWithPath: editedPath)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                   isDir.boolValue {
                    Task {
                        await viewModel.navigate(to: url)
                    }
                }
                isEditing = false
            }
            .onExitCommand {
                isEditing = false
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

    // MARK: - Actions

    /// Call this to enter editing mode (e.g. from Cmd+L).
    func startEditing() {
        editedPath = viewModel.state.currentDirectory.path
        isEditing = true
    }
}
