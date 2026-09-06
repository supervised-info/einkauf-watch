import Foundation
import WidgetKit

/// iPhone-App lädt das Homescreen-Widget neu, sobald Einkauf oder To-Do persistiert wurden.
///
/// Mehrere Requests in kurzer Folge (sofort + 80 ms Persist, beide Stores, WC-Burst,
/// `scenePhase == .active`) werden zu **einem** `reloadTimelines` zusammengezogen.
/// Der eigentliche WidgetCenter-Aufruf läuft nicht auf dem Main-Thread.
enum HomeWidgetReload {
    /// Trailing-Debounce: ein Reload nach dem letzten Request im Burst.
    private static let coalesceDelay: TimeInterval = 0.25
    private static let queue = DispatchQueue(label: "net.tschelle.einkauf.homeWidgetReload")
    private static var pending: DispatchWorkItem?

    static func timelines() {
        queue.async {
            pending?.cancel()
            let work = DispatchWorkItem {
                WidgetCenter.shared.reloadTimelines(ofKind: HomeWidgetSnapshot.widgetKind)
            }
            pending = work
            queue.asyncAfter(deadline: .now() + coalesceDelay, execute: work)
        }
    }
}
