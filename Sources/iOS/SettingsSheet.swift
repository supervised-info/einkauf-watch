import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var store: ShoppingStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.einkaufTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var newStapleName = ""
    @State private var newStoreName = ""
    @State private var confirmDeleteStore = false

    private var layout: [String] {
        StoreLayout.sanitized(store.state.currentStore.layout)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Hell, Dunkel oder System", selection: $appearance.theme) {
                        Text("Hell").tag(AppThemePreference.light)
                        Text("Dunkel").tag(AppThemePreference.dark)
                        Text("System").tag(AppThemePreference.system)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Hell, Dunkel oder System")
                    .einkaufRowChrome()

                    Picker("Creme oder Blau", selection: $appearance.palette) {
                        Text("Creme").tag(AppPalette.vintage)
                        Text("Blau").tag(AppPalette.navy)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Creme oder Blau")
                    .einkaufRowChrome()
                } header: {
                    Text("Darstellung")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Creme ist das Vintage-Papier, Blau die Navy-Palette. System folgt der iPhone-Einstellung für Hell und Dunkel.")
                }

                Section {
                    ForEach(store.stores) { s in
                        Button {
                            store.setStore(s.id)
                        } label: {
                            HStack {
                                Text(s.name)
                                    .foregroundStyle(theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if s.id == store.state.currentStoreId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(theme.oxide)
                                        .accessibilityLabel("ausgewählt")
                                }
                            }
                        }
                        .accessibilityLabel(s.name)
                        .accessibilityAddTraits(s.id == store.state.currentStoreId ? .isSelected : [])
                        .einkaufRowChrome()
                    }
                } header: {
                    Text("Aktueller Laden")
                        .foregroundStyle(theme.muted)
                }

                Section {
                    HStack {
                        TextField("Name des Ladens", text: $newStoreName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(submitStore)
                            .onChange(of: newStoreName) { _, value in
                                if value.count > StoreCatalog.nameMax {
                                    newStoreName = String(value.prefix(StoreCatalog.nameMax))
                                }
                            }
                        Button("Anlegen", action: submitStore)
                            .disabled(newStoreName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .einkaufRowChrome()
                } header: {
                    Text("Neuer Laden")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Übernimmt das Layout des ausgewählten Ladens.")
                }

                if !store.state.currentStore.builtin {
                    Section {
                        Button("Laden löschen", role: .destructive) {
                            confirmDeleteStore = true
                        }
                        .einkaufRowChrome()
                    }
                }

                Section {
                    ForEach(layout, id: \.self) { id in
                        layoutRow(id)
                            .moveDisabled(StoreLayout.isLocked(id))
                            .deleteDisabled(true)
                    }
                    .onMove { store.moveLayoutDepts(from: $0, to: $1) }
                } header: {
                    Text("Ladenweg · \(store.state.currentStore.name)")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Vor dem Einkauf immer vorn, Nach dem Einkauf immer hinten, Sonstiges direkt davor.")
                }
                .environment(\.editMode, .constant(.active))

                Section {
                    let unused = StoreLayout.unused(in: layout)
                    if unused.isEmpty {
                        Text("Alle Abteilungen sind im Layout.")
                            .foregroundStyle(theme.muted)
                            .einkaufRowChrome()
                    } else {
                        ForEach(unused, id: \.self) { id in
                            Button(Department.title(for: id)) {
                                store.addLayoutDept(id)
                            }
                            .foregroundStyle(theme.oxide)
                            .einkaufRowChrome()
                        }
                    }
                } header: {
                    Text("Abteilungen hinzufügen")
                        .foregroundStyle(theme.muted)
                }

                Section {
                    Button("Layout zurücksetzen") {
                        store.resetLayout()
                    }
                    .foregroundStyle(theme.oxide)
                    .einkaufRowChrome()
                }

                Section {
                    ForEach(Array(store.staples.enumerated()), id: \.offset) { idx, staple in
                        stapleRow(idx: idx, staple: staple)
                    }
                    HStack {
                        TextField("Milch, Butter…", text: $newStapleName)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit(submitStaple)
                        Button("Anlegen", action: submitStaple)
                            .disabled(newStapleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .einkaufRowChrome()
                } header: {
                    Text("Stamm-Artikel")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Stamm-Artikel erscheinen im Menü Stamm und können mit Gesamtliste auf einmal auf die Liste.")
                }

                Section {
                    NavigationLink {
                        KeywordDictionaryView()
                    } label: {
                        Text("Wörterbuch")
                    }
                    .einkaufRowChrome()
                }
            }
            .einkaufListChrome()
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog(
                "Laden „\(store.state.currentStore.name)“ wirklich löschen?",
                isPresented: $confirmDeleteStore,
                titleVisibility: .visible
            ) {
                Button("Laden löschen", role: .destructive) {
                    store.deleteStore(id: store.state.currentStoreId)
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func layoutRow(_ id: String) -> some View {
        let locked = StoreLayout.isLocked(id)
        HStack(spacing: 8) {
            Text(Department.title(for: id))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !locked {
                Button {
                    store.moveLayoutDept(id, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Nach oben")
                .disabled(!canMove(id, by: -1))

                Button {
                    store.moveLayoutDept(id, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Nach unten")
                .disabled(!canMove(id, by: 1))

                Button(role: .destructive) {
                    store.removeLayoutDept(id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Entfernen")
            }
        }
        .foregroundStyle(locked ? theme.muted : theme.ink)
        .einkaufRowChrome()
    }

    private func stapleRow(idx: Int, staple: Staple) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(staple.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    store.removeStaple(at: idx)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stamm-Artikel löschen")
            }
            Picker("Abteilung", selection: Binding(
                get: { Department.resolved(staple.dept) },
                set: { store.setStapleDept(at: idx, dept: $0) }
            )) {
                ForEach(Department.allCases) { dept in
                    Text(dept.title).tag(dept.rawValue)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Abteilung für \(staple.name)")
        }
        .padding(.vertical, 2)
        .einkaufRowChrome()
    }

    private func canMove(_ id: String, by: Int) -> Bool {
        let layout = self.layout
        guard let idx = layout.firstIndex(of: id) else { return false }
        let j = idx + by
        guard layout.indices.contains(j) else { return false }
        return !StoreLayout.isLocked(layout[j])
    }

    private func submitStaple() {
        store.createStaple(newStapleName)
        newStapleName = ""
    }

    private func submitStore() {
        store.createStore(newStoreName)
        newStoreName = ""
    }
}

#Preview {
    SettingsSheet()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environmentObject(AppearanceSettings())
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
