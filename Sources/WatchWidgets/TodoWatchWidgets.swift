import SwiftUI
import WidgetKit

/// Eigene WidgetKit-Complication für To-Do (`TodoProgress`), neben `EinkaufComplication`.
struct TodoComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoComplicationSnapshot.widgetKind, provider: TodoTimelineProvider()) { entry in
            TodoComplicationView(entry: entry)
                .widgetURL(TodoComplicationSnapshot.openURL)
        }
        .configurationDisplayName("To Do")
        .description("Offene Aufgaben der To-Do-Liste.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct TodoTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: TodoComplicationSnapshot
}

struct TodoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoTimelineEntry {
        TodoTimelineEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoTimelineEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoTimelineEntry>) -> Void) {
        let entry = makeEntry()
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> TodoTimelineEntry {
        let state = TodoPersistence.load() ?? .empty
        return TodoTimelineEntry(date: Date(), snapshot: .make(from: state))
    }
}

struct TodoComplicationView: View {
    var entry: TodoTimelineEntry
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
        .accessibilityHint("Öffnet To-Do")
    }

    private var circular: some View {
        Gauge(value: entry.snapshot.progress, in: 0...1) {
            Text(entry.snapshot.compactCountText)
        } currentValueLabel: {
            Text(entry.snapshot.compactCountText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(TodoComplicationSnapshot.labelText)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(entry.snapshot.compactCountText)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        ViewThatFits(in: .horizontal) {
            Text(entry.snapshot.inlineText)
            Text(entry.snapshot.compactCountText)
        }
        .widgetAccentable()
    }

    /// Ecke: offene Anzahl größer als das Label **To Do** (~19pt / ~11pt).
    private var corner: some View {
        Text(entry.snapshot.compactCountText)
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .widgetAccentable()
            .widgetLabel {
                Text(TodoComplicationSnapshot.labelText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .lineLimit(1)
            }
    }
}

#Preview(as: .accessoryCircular) {
    TodoComplication()
} timeline: {
    TodoTimelineEntry(date: .now, snapshot: .placeholder)
    TodoTimelineEntry(date: .now, snapshot: TodoComplicationSnapshot(openCount: 0, doneCount: 0, total: 0, isEmpty: true, progress: 0))
}

#Preview(as: .accessoryCorner) {
    TodoComplication()
} timeline: {
    TodoTimelineEntry(date: .now, snapshot: .placeholder)
}
