import WidgetKit

/// iPhone-App lädt das Homescreen-Widget neu, sobald `einkauf-local.json` geschrieben wurde.
enum HomeWidgetReload {
    static func timelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: HomeWidgetSnapshot.widgetKind)
    }
}
