import SwiftUI

/// Geh-Modus: große Checkbox + Name, flache Zeilenfolge (Laden + Position).
/// Digital Crown scrollt die `List`. Kein Edit-Chrome in v1.
struct WatchListView: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.einkaufTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if store.groups.isEmpty {
                    Text("Noch nichts auf der Liste.")
                        .font(.headline)
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List {
                        ForEach(store.walkListRows) { row in
                            switch row.line {
                            case .header(_, let dept):
                                Text(Department.title(for: dept))
                                    .foregroundStyle(theme.muted)
                                    .textCase(.uppercase)
                                    .listRowBackground(Color.clear)
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
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(theme.paper2)
                                .accessibilityLabel(item.name)
                                .accessibilityValue(item.done ? "erledigt" : "offen")
                            }
                        }
                    }
                    .einkaufListChrome()
                    .id("\(store.state.currentStoreId)|\(store.state.currentStore.layout.joined())")
                }
            }
            .navigationTitle(store.state.watchTitle)
            .id(store.state.currentStoreId)
            .navigationBarTitleDisplayMode(.inline)
            .containerBackground(theme.paper, for: .navigation)
        }
    }
}

#Preview {
    WatchListView()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
