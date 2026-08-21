import Foundation

/// Notification names shared across layers.
///
/// Lives in Core rather than the App layer because `Views` posts and observes
/// these; declaring them further up would make Views depend upward on App.
extension Notification.Name {
    package static let lcdrConfigurationApplied = Notification.Name("LCDR.configurationApplied")
}
