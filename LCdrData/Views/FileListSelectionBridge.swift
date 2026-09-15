import AppKit
import SwiftUI

/// Swallows the click on the blank area below the last row of a panel's file
/// list, so the list never drops its selection there.
///
/// `NSTableView` treats a click below the rows as "deselect everything", and
/// SwiftUI's list subclass does it regardless of `allowsEmptySelection`. The
/// panel does not want it — the cursor stays where it is — but putting the
/// selection back from the model is a round trip the user can see: the rows go
/// dark for a frame or two before they light up again, which reads as the whole
/// panel blinking. Stopping the click before the table sees it means there is
/// no deselection to undo.
///
/// The click still has to do the two things it legitimately did, so the monitor
/// does them itself: it makes the panel active and gives the list keyboard
/// focus.
struct FileListSelectionBridge: NSViewRepresentable {

    /// Called when a blank-area click is swallowed, so the panel can make
    /// itself active exactly as a click on a row would have.
    let onBlankClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = BridgeView()
        view.onBlankClick = onBlankClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BridgeView)?.onBlankClick = onBlankClick
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? BridgeView)?.stopMonitoring()
    }

    private final class BridgeView: NSView {

        var onBlankClick: (() -> Void)?

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
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, self.shouldSwallow(event) else { return event }
                self.onBlankClick?()
                if let table = self.tableView {
                    table.window?.makeFirstResponder(table)
                }
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        /// True for a click inside this panel's list that lands below every row.
        /// Clicks in another window, in the other panel, or on a row are left
        /// alone — the monitor is window-wide, so every one of those has to be
        /// ruled out here.
        private func shouldSwallow(_ event: NSEvent) -> Bool {
            guard let table = tableView,
                  let window = table.window,
                  event.window === window else { return false }

            let point = table.convert(event.locationInWindow, from: nil)
            guard table.bounds.contains(point) else { return false }
            // `row(at:)` reports -1 for a point past the last row, which is the
            // blank area this exists for. A click on a row is a real selection.
            return table.row(at: point) == -1
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
