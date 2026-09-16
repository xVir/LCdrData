import AppKit
import SwiftUI

/// Intercepts pointer events on a panel's file list before `NSTableView` sees them.
///
/// Two jobs, both because SwiftUI's `List` does not match the panel's cursor rules:
///
/// 1. **Blank-area primary click.** `NSTableView` treats a click below the rows as
///    "deselect everything", and SwiftUI's list subclass does it regardless of
///    `allowsEmptySelection`. The panel does not want it — the cursor stays where
///    it is — but putting the selection back from the model is a round trip the
///    user can see: the rows go dark for a frame or two before they light up
///    again, which reads as the whole panel blinking. Stopping the click before
///    the table sees it means there is no deselection to undo. The click still
///    has to make the panel active and give the list keyboard focus, so the
///    monitor does those itself.
///
/// 2. **Secondary click on a row.** A right-click or Control-click on a row that
///    is not already selected must collapse the selection to that row *before*
///    the context menu is built. SwiftUI's `.contextMenu(forSelectionType:)`
///    does not do this, so a multi-selection would otherwise survive and the
///    menu would act on the old set. A secondary click on a row that *is*
///    selected is left alone. Blank-area secondary clicks are not swallowed —
///    they still open the background menu.
struct FileListSelectionBridge: NSViewRepresentable {

    /// Called when this panel should become the active panel: a swallowed
    /// blank-area primary click, or a secondary click on a row.
    let onActivatePanel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = BridgeView()
        view.onActivatePanel = onActivatePanel
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BridgeView)?.onActivatePanel = onActivatePanel
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? BridgeView)?.stopMonitoring()
    }

    private final class BridgeView: NSView {

        var onActivatePanel: (() -> Void)?

        private var monitor: Any?
        private weak var tableView: NSTableView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                stopMonitoring()
                return
            }
            // The list is not in the hierarchy yet while this view is being
            // added to the window, so the lookup waits a turn.
            DispatchQueue.main.async { [weak self] in
                self?.startMonitoring()
            }
        }

        func startMonitoring() {
            guard monitor == nil, let table = enclosingTableView() else { return }
            tableView = table
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if self.isSecondaryClick(event) {
                    self.handleSecondaryClick(event)
                    return event
                }
                if self.isPrimaryRowClick(event) {
                    self.activatePanel()
                    return event
                }
                guard self.shouldSwallowPrimaryBlankClick(event) else { return event }
                self.activatePanel()
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        /// Right-click, or Control-click (which AppKit delivers as a left mouse
        /// down with the Control modifier).
        private func isSecondaryClick(_ event: NSEvent) -> Bool {
            if event.type == .rightMouseDown { return true }
            return event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        }

        /// Collapses the table selection to the row under the pointer when that
        /// row is not already selected, and activates the panel either way.
        /// Blank-area secondary clicks are ignored here so the background menu
        /// can still open.
        private func handleSecondaryClick(_ event: NSEvent) {
            guard let table = tableView,
                  let window = table.window,
                  event.window === window else { return }

            let point = table.convert(event.locationInWindow, from: nil)
            guard table.bounds.contains(point) else { return }
            let row = table.row(at: point)
            guard row >= 0 else { return }

            activatePanel()
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }

        /// True for a primary click inside this panel's list that lands below
        /// every row. Clicks in another window, in the other panel, or on a row
        /// are left alone — the monitor is window-wide, so every one of those
        /// has to be ruled out here.
        private func shouldSwallowPrimaryBlankClick(_ event: NSEvent) -> Bool {
            guard let table = tableView,
                  let window = table.window,
                  event.window === window else { return false }

            let point = table.convert(event.locationInWindow, from: nil)
            guard table.bounds.contains(point) else { return false }
            // `row(at:)` reports -1 for a point past the last row, which is the
            // blank area this exists for. A click on a row is a real selection.
            return table.row(at: point) == -1
        }

        private func isPrimaryRowClick(_ event: NSEvent) -> Bool {
            guard let table = tableView,
                  let window = table.window,
                  event.window === window else { return false }

            let point = table.convert(event.locationInWindow, from: nil)
            guard table.bounds.contains(point) else { return false }
            return table.row(at: point) >= 0
        }

        private func activatePanel() {
            onActivatePanel?()
            if let table = tableView {
                table.window?.makeFirstResponder(table)
            }
        }

        /// The nearest table in the hierarchy: climb ancestors until a level's
        /// subtree holds exactly one, so a sibling panel's table can never win.
        private func enclosingTableView() -> NSTableView? {
            var ancestor: NSView? = superview
            while let view = ancestor {
                let tables = view.descendantTableViews()
                if tables.count == 1 { return tables.first }
                if tables.count > 1 { return nil }
                ancestor = view.superview
            }
            return nil
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private extension NSView {
    func descendantTableViews() -> [NSTableView] {
        if let table = self as? NSTableView { return [table] }
        return subviews.flatMap { $0.descendantTableViews() }
    }
}
