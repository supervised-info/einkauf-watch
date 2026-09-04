import WidgetKit

/// Watch-App lädt WidgetKit-Complications neu nach Persistenz.
/// Einkauf und To-Do sind eigene kinds — ein Reload darf die andere Domain nicht ersetzen.
enum WatchComplicationReload {
    static func timelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: ComplicationSnapshot.widgetKind)
    }

    static func todoTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: TodoComplicationSnapshot.widgetKind)
    }
}
