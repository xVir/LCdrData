import AppKit
import SwiftUI

/// Reaches the hosting `NSWindow` so window-level chrome can be configured —
/// there is no SwiftUI modifier for `titlebarSeparatorStyle`.
///
/// The window is not available while the view is being made, so the callback
/// runs once the view has been added to a window.
struct WindowConfigurator: NSViewRepresentable {

    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CallbackView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CallbackView else { return }
        view.configure = configure
        // The closure captures view state, so a changed one must be re-applied
        // rather than merely stored against the next move into a window.
        if let window = view.window {
            configure(window)
        }
    }

    private final class CallbackView: NSView {
        var configure: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                configure?(window)
            }
        }
    }
}
