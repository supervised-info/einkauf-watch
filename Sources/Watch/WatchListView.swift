import SwiftUI

/// Geh-Modus: große Checkbox + Name, nach Abteilung gruppiert.
/// Digital Crown scrollt die `List`. Kein Edit-Chrome in v1.
struct WatchListView: View {
    @EnvironmentObject private var store: ShoppingStore

    var body: some View {
        NavigationStack {
            Group {
                if store.groups.isEmpty {
                    Text("Noch nichts auf der Liste.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List {
                        ForEach(store.groups) { group in
                            Section(group.title) {
                                ForEach(group.items) { item in
                                    Button {
                                        store.toggle(item.id)
                                    } label: {
                                        HStack(alignment: .center, spacing: 10) {
                                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                                .font(.title)
                                                .foregroundStyle(item.done ? Color.green : Color.secondary)
                                                .frame(width: 36, height: 36)
                                            Text(item.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .strikethrough(item.done)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                    .accessibilityLabel(item.name)
                                    .accessibilityValue(item.done ? "erledigt" : "offen")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Einkauf")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    WatchListView()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
}
