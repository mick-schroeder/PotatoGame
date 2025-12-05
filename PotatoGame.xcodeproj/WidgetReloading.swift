import Foundation
#if canImport(WidgetKit)
    import WidgetKit
#endif

/// Helper for reloading Potato Game widgets when data changes.
public enum WidgetReloading {
    /// Reload all timelines for the Potato Game widget kind.
    public static func reloadAllPotatoWidgets() {
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "PotatoGameWidget")
        #endif
    }

    /// Reload timelines for a specific widget kind. Defaults to PotatoGameWidget kind.
    /// - Parameter kind: The widget kind identifier to reload.
    public static func reloadPotatoWidgetKind(_ kind: String = "PotatoGameWidget") {
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}
