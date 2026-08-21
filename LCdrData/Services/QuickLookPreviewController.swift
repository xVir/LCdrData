import AppKit
import QuickLookUI

/// Presents the system Quick Look panel for a file URL.
@MainActor
package final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource {

    private var previewURL: URL?

    package func show(url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.currentPreviewItemIndex = 0
        panel.refreshCurrentPreviewItem()
        panel.makeKeyAndOrderFront(nil)
    }

    package func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    package func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let previewURL else { return nil }
        return previewURL as NSURL
    }
}
