import WidgetKit

/// iPhone-App lädt das Homescreen-Widget neu, sobald Einkauf oder To-Do persistiert wurden.
enum HomeWidgetReload {
    static func timelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: HomeWidgetSnapshot.widgetKind)
    }
}
