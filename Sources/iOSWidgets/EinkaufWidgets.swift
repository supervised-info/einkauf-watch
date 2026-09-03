import SwiftUI
import WidgetKit

@main
struct EinkaufWidgets: WidgetBundle {
    var body: some Widget {
        EinkaufHomeWidget()
    }
}

/// Homescreen-Widget (iOS 17, nicht Watch, nicht Sperrbildschirm). Tippen öffnet die iPhone-App.
struct EinkaufHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetSnapshot.widgetKind, provider: EinkaufHomeTimelineProvider()) { entry in
            EinkaufHomeWidgetView(entry: entry)
                .widgetURL(HomeWidgetSnapshot.openURL)
        }
        .configurationDisplayName("Einkauf")
        .description("Laden und Fortschritt der Einkaufsliste.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct EinkaufHomeTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeWidgetSnapshot
}

struct EinkaufHomeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> EinkaufHomeTimelineEntry {
        EinkaufHomeTimelineEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (EinkaufHomeTimelineEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EinkaufHomeTimelineEntry>) -> Void) {
        let entry = makeEntry()
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> EinkaufHomeTimelineEntry {
        let state = Persistence.load() ?? .seed
        return EinkaufHomeTimelineEntry(date: Date(), snapshot: .make(from: state))
    }
}

struct EinkaufHomeWidgetView: View {
    var entry: EinkaufHomeTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color.clear
        }
        .accessibilityLabel(entry.snapshot.accessibilityLabel)
        .accessibilityHint("Öffnet die Einkaufsliste")
    }

    /// Klein: Ladenname plus `xx/yy`.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.snapshot.storeName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(entry.snapshot.progressLabel)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
    }

    /// Mittel: Laden, `xx/yy`, danach die nächsten offenen Artikel in Geh-Modus-Reihenfolge.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.snapshot.storeName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(entry.snapshot.progressLabel)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            ForEach(Array(entry.snapshot.openItemNames.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }
}

#Preview(as: .systemSmall) {
    EinkaufHomeWidget()
} timeline: {
    EinkaufHomeTimelineEntry(date: .now, snapshot: .placeholder)
    EinkaufHomeTimelineEntry(date: .now, snapshot: HomeWidgetSnapshot(progressLabel: "0/0", storeName: "Edeka", isEmpty: true, openItemNames: []))
}

#Preview(as: .systemMedium) {
    EinkaufHomeWidget()
} timeline: {
    EinkaufHomeTimelineEntry(date: .now, snapshot: .placeholder)
}
