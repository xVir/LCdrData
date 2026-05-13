import Foundation

/// Describes which kind of access request is being made. Drives alert copy,
/// button labels, and the `NSOpenPanel.directoryURL` for the presenter.
enum AccessRequestContext: Sendable, Equatable {

    /// First-launch prompt for Home folder access.
    case startup

    /// Reactive prompt fired when a user-initiated navigation hit a permission
    /// denial. `displayURL` is the path the user clicked (may be a symlink);
    /// `resolvedTarget` is the canonical folder the bookmark will cover.
    case reactive(displayURL: URL, resolvedTarget: URL)

    /// User-initiated grant from the "Grant Folder Access…" menu item.
    /// `suggestedURL` is where the NSOpenPanel initially navigates.
    case manualGrant(suggestedURL: URL)

    /// The resolved-target URL this request is conceptually about — used as
    /// the dedup key for single-flight coalescing across concurrent callers.
    var dedupKey: URL {
        switch self {
        case .startup:
            return FileManager.default.homeDirectoryForCurrentUser
        case .reactive(_, let resolvedTarget):
            return resolvedTarget
        case .manualGrant(let suggestedURL):
            return suggestedURL.resolvingSymlinksInPath()
        }
    }
}
