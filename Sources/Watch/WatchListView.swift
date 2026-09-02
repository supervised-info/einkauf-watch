import SwiftUI

/// Geh-Modus: große Checkbox + Name, nach Abteilung gruppiert.
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
                        ForEach(store.groups) { group in
                            Section {
                                ForEach(group.items) { item in
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
                            } header: {
                                Text(group.title)
                                    .foregroundStyle(theme.muted)
                            }
                        }
                    }
                    .einkaufListChrome()
                }
            }
            .navigationTitle("Einkauf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(store.state.progressLabel)
                        .font(.headline)
                        .foregroundStyle(theme.muted)
                        .monospacedDigit()
                        .accessibilityLabel("\(store.state.doneCount) von \(store.state.items.count)")
                }
            }
            .containerBackground(theme.paper, for: .navigation)
        }
    }
}

#Preview {
    WatchListView()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
