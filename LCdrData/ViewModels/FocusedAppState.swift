import SwiftUI

/// Exposes the active `AppState` as a focused scene value.
///
/// Lives beside `AppState` rather than in the App layer because `Views` reads
/// `@FocusedValue(\.appState)`; declaring it further up would make Views depend
/// upward on App.
package struct ActiveAppStateKey: FocusedValueKey {
    package typealias Value = AppState
}

extension FocusedValues {
    package var appState: AppState? {
        get { self[ActiveAppStateKey.self] }
        set { self[ActiveAppStateKey.self] = newValue }
    }
}
