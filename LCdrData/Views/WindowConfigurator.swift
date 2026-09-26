import AppKit
import SwiftUI
import ViewModels

/// Reaches the hosting `NSWindow` so window-level chrome can be configured —
/// there is no SwiftUI modifier for `titlebarSeparatorStyle`.
///
/// The window is not available while the view is being made, so the callback
/// runs once the view has been added to a window.
struct WindowConfigurator: NSViewRepresentable {

    let showsTabStrip: Bool
    let operations: FileOperationViewModel

    func makeNSView(context: Context) -> NSView {
        let view = CallbackView()
        view.showsTabStrip = showsTabStrip
        view.operations = operations
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CallbackView else { return }
        view.showsTabStrip = showsTabStrip
        view.operations = operations
        if let window = view.window {
            view.apply(to: window)
        }
    }

    private final class CallbackView: NSView {
        var showsTabStrip = false
        var operations: FileOperationViewModel?
        private var closeGuard: WindowCloseGuard?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                apply(to: window)
            }
        }

        func apply(to window: NSWindow) {
            window.titlebarSeparatorStyle = showsTabStrip ? .none : .automatic
            installIndicator(on: window)
            installCloseGuard(on: window)
        }

        private func installIndicator(on window: NSWindow) {
            guard let operations else { return }
            if window.titlebarAccessoryViewControllers.contains(where: { $0 is TaskIndicatorAccessory }) {
                return
            }
            window.addTitlebarAccessoryViewController(TaskIndicatorAccessory(operations: operations))
        }

        private func installCloseGuard(on window: NSWindow) {
            let guardObject: WindowCloseGuard
            if let existing = window.delegate as? WindowCloseGuard {
                guardObject = existing
            } else {
                let created = WindowCloseGuard()
                created.original = window.delegate
                window.delegate = created
                guardObject = created
            }
            closeGuard = guardObject
            guardObject.operations = operations
        }
    }
}

private final class TaskIndicatorAccessory: NSTitlebarAccessoryViewController {
    init(operations: FileOperationViewModel) {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
        let host = TitlebarIndicatorHostingView(
            rootView: TaskIndicatorButton(operations: operations)
        )
        host.operations = operations
        host.frame.size = NSSize(width: 28, height: 22)
        view = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Title-bar clicks otherwise drag the window, so the ring never receives them.
private final class TitlebarIndicatorHostingView: NSHostingView<TaskIndicatorButton> {
    var operations: FileOperationViewModel?

    override var mouseDownCanMoveWindow: Bool { false }

    /// The title bar otherwise draws this control in white, like a template image.
    override var allowsVibrancy: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        operations?.toggleTaskList()
    }

    override func accessibilityPerformPress() -> Bool {
        operations?.toggleTaskList()
        return true
    }
}

private final class WindowCloseGuard: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    var operations: FileOperationViewModel?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let operations, operations.hasUnfinishedBackgroundTasks {
            let alert = NSAlert()
            alert.messageText = "File operations are still running"
            alert.informativeText = "Closing stops them. Items already finished stay finished, and operations that have not started will not run."
            alert.addButton(withTitle: "Cancel and Close")
            alert.addButton(withTitle: "Keep Open")
            if alert.runModal() != .alertFirstButtonReturn {
                return false
            }
            operations.cancelAllUnfinished()
        }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original
    }
}
