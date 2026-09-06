import SwiftUI
import WidgetKit

@main
struct EinkaufWidgets: WidgetBundle {
    var body: some Widget {
        EinkaufHomeWidget()
    }
}

/// Homescreen-Widget (iOS 17, nicht Watch, nicht Sperrbildschirm).
/// Klein: zwei gestapelte Blöcke (Label, darunter `oo/xx/yy`). Mittel/Groß: Mini-Tabelle.
struct EinkaufHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HomeWidgetSnapshot.widgetKind, provider: EinkaufHomeTimelineProvider()) { entry in
            EinkaufHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Einkauf")
        .description("Einkauf und To-Do: offen, erledigt, gesamt.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
        // Kaputtes / leeres JSON → Seed bzw. empty, nie throw/crash.
        let einkauf = Persistence.load() ?? .seed
        let todo = TodoPersistence.load() ?? .empty
        let listId = TodoCurrentList.iphoneWidgetId
        return EinkaufHomeTimelineEntry(
            date: Date(),
            snapshot: .make(from: einkauf, todo: todo, currentListId: listId)
        )
    }
}

struct EinkaufHomeWidgetView: View {
    var entry: EinkaufHomeTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium, .systemLarge:
                table
            default:
                small
                    .widgetURL(HomeWidgetSnapshot.openURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color.clear
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.snapshot.accessibilityLabel)
        .accessibilityHint(family == .systemSmall ? "Öffnet die Einkaufsliste" : "Öffnet Einkauf oder To-Do")
    }

    /// Klein: `Einkaufsliste` (sonst `Einkauf`) und `To Do (<Liste>)` als gestapelte Blöcke.
    /// Pro Domain Label in eigener Zeile, darunter `oo/xx/yy`. Abstand dazwischen.
    private var small: some View {
        VStack(alignment: .leading, spacing: 12) {
            stackedBlock {
                ViewThatFits(in: .horizontal) {
                    Text(HomeWidgetSnapshot.einkaufLabel)
                    Text(HomeWidgetSnapshot.einkaufLabelCompact)
                }
            } counts: {
                Text(entry.snapshot.einkauf.progressLabel)
            }
            stackedBlock {
                Text(entry.snapshot.todoRowLabel)
            } counts: {
                Text(entry.snapshot.todo.progressLabel)
            }
        }
    }

    /// Eine Label-Schrift für beide Small-Blöcke.
    private var smallLabelFont: Font { .caption }

    /// Eine Zähler-Schrift für beide Small-Blöcke (`oo/xx/yy`).
    private var smallCountsFont: Font { .system(.headline, design: .rounded).weight(.semibold) }

    /// Mittel/Groß: dieselben zwei Domains, Spalten Offen | Erledigt | Gesamt.
    private var table: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            headerRow
            Link(destination: HomeWidgetSnapshot.openURL) {
                dataRow(label: HomeWidgetSnapshot.einkaufLabelCompact, counts: entry.snapshot.einkauf)
            }
            Link(destination: HomeWidgetSnapshot.todoURL) {
                dataRow(label: entry.snapshot.todoRowLabel, counts: entry.snapshot.todo)
            }
            Spacer(minLength: 0)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("")
                .frame(maxWidth: .infinity, alignment: .leading)
            headerCell(HomeWidgetSnapshot.columnHeaders.0)
            headerCell(HomeWidgetSnapshot.columnHeaders.1)
            headerCell(HomeWidgetSnapshot.columnHeaders.2)
        }
    }

    /// Ein Domain-Block: Caption-Label, darunter Headline-Zähler — nicht nebeneinander.
    private func stackedBlock<Label: View, Counts: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder counts: () -> Counts
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label()
                .font(smallLabelFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            counts()
                .font(smallCountsFont)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dataRow(label: String, counts: HomeWidgetCounts) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            countCell(counts.open)
            countCell(counts.done)
            countCell(counts.total)
        }
    }

    private func headerCell(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: columnWidth, alignment: .trailing)
    }

    private func countCell(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: columnWidth, alignment: .trailing)
    }

    private var columnWidth: CGFloat {
        family == .systemLarge ? 64 : 52
    }
}

#Preview(as: .systemSmall) {
    EinkaufHomeWidget()
} timeline: {
    EinkaufHomeTimelineEntry(date: .now, snapshot: .placeholder)
    EinkaufHomeTimelineEntry(
        date: .now,
        snapshot: HomeWidgetSnapshot(
            einkauf: HomeWidgetCounts(open: 0, done: 0, total: 0),
            todo: HomeWidgetCounts(open: 0, done: 0, total: 0),
            todoListName: TodoListFilter.allTitle
        )
    )
}

#Preview(as: .systemMedium) {
    EinkaufHomeWidget()
} timeline: {
    EinkaufHomeTimelineEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    EinkaufHomeWidget()
} timeline: {
    EinkaufHomeTimelineEntry(date: .now, snapshot: .placeholder)
}
