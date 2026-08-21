import SwiftUI

private struct PanelDateFormatKey: EnvironmentKey {
    package static var defaultValue: String { "yyyy-MM-dd HH:mm" }
}

private struct PanelFontSizeKey: EnvironmentKey {
    package static var defaultValue: CGFloat { 13 }
}

package extension EnvironmentValues {
    package var lcPanelDateFormat: String {
        get { self[PanelDateFormatKey.self] }
        set { self[PanelDateFormatKey.self] = newValue }
    }

    package var lcPanelFontSize: CGFloat {
        get { self[PanelFontSizeKey.self] }
        set { self[PanelFontSizeKey.self] = newValue }
    }
}
