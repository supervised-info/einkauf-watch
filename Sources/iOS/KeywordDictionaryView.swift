import SwiftUI

/// Mitgelieferte Wörter nur lesen; eigene Zuordnungen aus `state.mappings` (Backup-Feld `mappings`).
struct KeywordDictionaryView: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.einkaufTheme) private var theme
    @State private var query = ""
    @State private var newName = ""
    @State private var newDept = Department.sonstiges.rawValue

    private var groups: [KeywordDictionary.Group] {
        KeywordDictionary.groups(from: KeywordDictionary.source, matching: query)
    }

    private var learned: [KeywordDictionary.LearnedMapping] {
        KeywordDictionary.learnedMappings(from: store.state.mappings, matching: query)
    }

    var body: some View {
        List {
            Section {
                if store.state.mappings.isEmpty {
                    Text("Noch keine eigenen Zuordnungen. Abteilung im Bearbeiten-Modus ändern — dann erscheint der Name hier.")
                        .foregroundStyle(theme.muted)
                        .einkaufRowChrome()
                        .deleteDisabled(true)
                } else {
                    ForEach(learned) { row in
                        mappingRow(row)
                    }
                    .onDelete(perform: deleteMappings)
                }
                HStack {
                    TextField("Name, z. B. Milch", text: $newName)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit(submitMapping)
                    Picker("Abteilung", selection: $newDept) {
                        ForEach(Department.allCases) { dept in
                            Text(dept.title).tag(dept.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("Abteilung für neue Zuordnung")
                    Button("Hinzufügen", action: submitMapping)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .einkaufRowChrome()
                .deleteDisabled(true)
            } header: {
                Text("Meine Zuordnungen")
                    .foregroundStyle(theme.muted)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.words, id: \.self) { word in
                        Text(word)
                            .einkaufRowChrome()
                    }
                } header: {
                    Text(group.title)
                        .foregroundStyle(theme.muted)
                }
            }
            Section {
            } footer: {
                Text("Die mitgelieferte Wortliste ist fest. Eigene Zuordnungen stehen im Backup als mappings und gewinnen beim nächsten Eintragen. Sonderregeln (TK, Eistee, Schorle, Chips, Eis) stehen nicht in dieser Liste. Eigene Korrekturen merkt sich die App unter dem Artikelnamen (ohne Menge) und nutzt sie beim nächsten Eintragen; das Wörterbuch selbst ändert sich nicht.")
            }
        }
        .einkaufListChrome()
        .navigationTitle("Wörterbuch")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Wort suchen")
    }

    private func mappingRow(_ row: KeywordDictionary.LearnedMapping) -> some View {
        HStack {
            Text(row.key)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Abteilung", selection: Binding(
                get: { Department.resolved(row.dept) },
                set: { store.setMapping(row.key, dept: $0) }
            )) {
                ForEach(Department.allCases) { dept in
                    Text(dept.title).tag(dept.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Abteilung für \(row.key)")
        }
        .padding(.vertical, 2)
        .einkaufRowChrome()
    }

    private func deleteMappings(at offsets: IndexSet) {
        let keys = offsets.compactMap { learned.indices.contains($0) ? learned[$0].key : nil }
        for key in keys {
            store.removeMapping(key)
        }
    }

    private func submitMapping() {
        store.setMapping(newName, dept: newDept)
        newName = ""
    }
}

#Preview {
    NavigationStack {
        KeywordDictionaryView()
    }
    .environmentObject(ShoppingStore(state: .seed, enableSync: false))
    .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
