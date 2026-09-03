import SwiftUI

/// Geh-Modus: große Checkbox + Name, flache Zeilenfolge (Laden + Position).
/// Digital Crown scrollt die `List`. Kein Edit-Chrome in v1.
struct WatchListView: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.einkaufTheme) private var theme
    /// Nur Watch-UserDefaults — nicht im Backup, nicht zum iPhone.
    @AppStorage("einkauf.watch.hideCompleted") private var hideCompleted = false

    private var visibleWalkRows: [WalkListRow] {
        store.walkListRows(hidingCompleted: hideCompleted)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hideCompletedBar
                Group {
                    if store.groups.isEmpty {
                        Text("Noch nichts auf der Liste.")
                            .font(.headline)
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if visibleWalkRows.isEmpty {
                        Text("Erledigte ausgeblendet.")
                            .font(.headline)
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        List {
                            ForEach(visibleWalkRows) { row in
                                switch row.line {
                                case .header(_, let dept):
                                    Text(Department.title(for: dept))
                                        .foregroundStyle(theme.muted)
                                        .textCase(.uppercase)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                        .accessibilityAddTraits(.isHeader)
                                        .accessibilityLabel(Department.title(for: dept))
                                case .item(_, let item):
                                    Button {
                                        store.toggle(item.id)
                                    } label: {
                                        HStack(alignment: .center, spacing: 10) {
                                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                                .font(.title)
                                                .foregroundStyle(item.done ? theme.good : theme.muted)
                                                .frame(width: 36, height: 36)
                                            Text(item.name)
                                                .font(.headline)
                                                .foregroundStyle(theme.ink)
                                                .strikethrough(item.done, color: theme.muted)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                    .listRowBackground(theme.paper2)
                                    .accessibilityLabel(item.name)
                                    .accessibilityValue(item.done ? "erledigt" : "offen")
                                }
                            }
                        }
                        .einkaufListChrome()
                        .contentMargins(.top, 0, for: .scrollContent)
                        .id("\(store.state.currentStoreId)|\(store.state.currentStore.layout.joined())")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(store.state.watchTitle)
            .id(store.state.currentStoreId)
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(theme.paper, for: .navigation)
        }
    }

    /// Chrome direkt unter dem Titel, rechts: nicht in der Toolbar (Leading kürzt xx/yy, Trailing frisst die Uhr).
    /// Kompakte Zeile (~24pt) — kein 44pt-minHeight, sonst leere Bänder über und unter dem Glyph.
    private var hideCompletedBar: some View {
        HStack(spacing: 0) {
            Spacer()
            Button {
                hideCompleted.toggle()
            } label: {
                Image(systemName: hideCompleted ? "eye.slash" : "eye")
                    .font(.caption)
                    .imageScale(.small)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hideCompleted ? "Erledigte einblenden" : "Erledigte ausblenden")
        }
        .frame(height: 24)
    }
}

#Preview {
    WatchListView()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
