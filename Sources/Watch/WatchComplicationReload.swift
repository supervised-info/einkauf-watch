import WidgetKit

/// Watch-App lädt WidgetKit-Complications neu, sobald `einkauf-local.json` geschrieben wurde.
enum WatchComplicationReload {
    static func timelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: ComplicationSnapshot.widgetKind)
    }
}
