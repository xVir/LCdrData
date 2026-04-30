import SwiftUI

private struct PanelDateFormatKey: EnvironmentKey {
    static var defaultValue: String { "yyyy-MM-dd HH:mm" }
}

private struct PanelFontSizeKey: EnvironmentKey {
    static var defaultValue: CGFloat { 13 }
}

extension EnvironmentValues {
    var lcPanelDateFormat: String {
        get { self[PanelDateFormatKey.self] }
        set { self[PanelDateFormatKey.self] = newValue }
    }

    var lcPanelFontSize: CGFloat {
        get { self[PanelFontSizeKey.self] }
        set { self[PanelFontSizeKey.self] = newValue }
    }
}
