import SwiftUI

/// Einstellungen → Gespeicherte Listen → **Liste bearbeiten**.
/// Name + Vorlagen-Artikel (`name`/`dept`). **Übernehmen** füllt auf, ersetzt nicht.
struct SavedListEditView: View {
    let listId: String
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.einkaufTheme) private var theme
    @State private var newItemName = ""

    private var list: SavedList? {
        store.savedLists.first { $0.id == listId }
    }

    var body: some View {
        List {
            if let list {
                Section {
                    TextField("Name, z. B. Grillen", text: nameBinding(list))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .einkaufRowChrome()
                } header: {
                    Text("Name")
                        .foregroundStyle(theme.muted)
                }

                Section {
                    if list.items.isEmpty {
                        Text("Keine Artikel in dieser Liste.")
                            .foregroundStyle(theme.muted)
                            .einkaufRowChrome()
                            .deleteDisabled(true)
                    } else {
                        ForEach(Array(list.items.enumerated()), id: \.offset) { idx, item in
                            savedItemRow(idx: idx, item: item)
                        }
                        .onDelete(perform: deleteItems)
                    }
                    HStack {
                        TextField("Milch, Äpfel…", text: $newItemName)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit(submitItem)
                        Button("Hinzufügen", action: submitItem)
                            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .einkaufRowChrome()
                    .deleteDisabled(true)
                } header: {
                    Text("Artikel")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Nur Name und Abteilung, ohne Häkchen. Übernehmen füllt die aktuelle Einkaufsliste auf, ohne sie zu ersetzen.")
                }
            } else {
                Text("Diese Liste gibt es nicht mehr.")
                    .foregroundStyle(theme.muted)
                    .einkaufRowChrome()
            }
        }
        .einkaufListChrome()
        .navigationTitle("Liste bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Übernehmen") {
                    if let list {
                        store.applySavedList(list)
                    }
                }
                .disabled(list == nil || list?.items.isEmpty == true)
            }
        }
    }

    private func nameBinding(_ list: SavedList) -> Binding<String> {
        Binding(
            get: { list.name },
            set: { store.renameSavedList(id: listId, name: $0) }
        )
    }

    private func savedItemRow(idx: Int, item: Staple) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: itemNameBinding(idx: idx, item: item))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    store.removeSavedListItem(id: listId, at: idx)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Artikel löschen")
            }
            Picker("Abteilung", selection: Binding(
                get: { Department.resolved(item.dept) },
                set: { store.setSavedListItemDept(id: listId, at: idx, dept: $0) }
            )) {
                ForEach(Department.allCases) { dept in
                    Text(dept.title).tag(dept.rawValue)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Abteilung für \(item.name)")
        }
        .padding(.vertical, 2)
        .einkaufRowChrome()
    }

    private func itemNameBinding(idx: Int, item: Staple) -> Binding<String> {
        Binding(
            get: { item.name },
            set: { store.renameSavedListItem(id: listId, at: idx, to: $0) }
        )
    }

    private func deleteItems(at offsets: IndexSet) {
        for idx in offsets.sorted(by: >) {
            store.removeSavedListItem(id: listId, at: idx)
        }
    }

    private func submitItem() {
        store.addSavedListItem(id: listId, name: newItemName)
        newItemName = ""
    }
}

#Preview {
    NavigationStack {
        SavedListEditView(listId: "l1")
    }
    .environmentObject(ShoppingStore(
        state: {
            var seed = AppState.seed
            seed.savedLists = [
                SavedList(
                    id: "l1",
                    name: "Grillen",
                    items: [
                        Staple(name: "Milch", dept: "kuehlung"),
                        Staple(name: "Grillkohle", dept: "sonstiges")
                    ]
                )
            ]
            return seed
        }(),
        enableSync: false
    ))
    .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
