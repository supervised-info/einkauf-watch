import SwiftUI
import WidgetKit

@main
struct EinkaufWatchWidgets: WidgetBundle {
    var body: some Widget {
        EinkaufComplication()
    }
}

/// WidgetKit-Complication (watchOS 10, kein ClockKit). Tippen öffnet die Watch-App im Geh-Modus.
struct EinkaufComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationSnapshot.widgetKind, provider: EinkaufTimelineProvider()) { entry in
            EinkaufComplicationView(entry: entry)
                .widgetURL(ComplicationSnapshot.openURL)
        }
        .configurationDisplayName("Einkauf")
        .description("Fortschritt der Einkaufsliste, erledigt/gesamt.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct EinkaufTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot
}

struct EinkaufTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> EinkaufTimelineEntry {
        EinkaufTimelineEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (EinkaufTimelineEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EinkaufTimelineEntry>) -> Void) {
        let entry = makeEntry()
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> EinkaufTimelineEntry {
        let state = Persistence.load() ?? .seed
        return EinkaufTimelineEntry(date: Date(), snapshot: .make(from: state))
    }
}

struct EinkaufComplicationView: View {
    var entry: EinkaufTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .accessoryRectangular:
                rectangular
            case .accessoryInline:
                inline
            case .accessoryCorner:
                corner
            default:
                circular
            }
        }
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel(entry.snapshot.accessibilityLabel)
        .accessibilityHint("Öffnet die Einkaufsliste")
    }

    /// Runde Komplikation: Gauge 0…1, kleines `xx` über `yy` in der Mitte.
    /// Kein `.title2` — auf der physischen Watch zeichnet watchOS sonst „!“.
    private var circular: some View {
        Gauge(value: entry.snapshot.progress, in: 0...1) {
            Text(entry.snapshot.progressLabel)
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(entry.snapshot.doneText)
                    .lineLimit(1)
                Text(entry.snapshot.totalText)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    /// Rechteck: kurzer Ladenname plus `xx/yy`.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.snapshot.storeName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(entry.snapshot.progressLabel)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline-Zeile: Laden + Zähler, sonst nur `xx/yy`.
    private var inline: some View {
        ViewThatFits(in: .horizontal) {
            Text(entry.snapshot.inlineText)
            Text(entry.snapshot.progressLabel)
        }
        .widgetAccentable()
    }

    /// Ecke: kleines `xx/yy` im Bogen, Ladenname am Label.
    private var corner: some View {
        Text(entry.snapshot.progressLabel)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .widgetAccentable()
            .widgetLabel {
                Text(entry.snapshot.storeName)
                    .lineLimit(1)
            }
    }
}

#Preview(as: .accessoryCircular) {
    EinkaufComplication()
} timeline: {
    EinkaufTimelineEntry(date: .now, snapshot: .placeholder)
    EinkaufTimelineEntry(date: .now, snapshot: ComplicationSnapshot(progressLabel: "0/0", storeName: "Edeka", isEmpty: true))
}

#Preview(as: .accessoryRectangular) {
    EinkaufComplication()
} timeline: {
    EinkaufTimelineEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryInline) {
    EinkaufComplication()
} timeline: {
    EinkaufTimelineEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryCorner) {
    EinkaufComplication()
} timeline: {
    EinkaufTimelineEntry(date: .now, snapshot: .placeholder)
}
