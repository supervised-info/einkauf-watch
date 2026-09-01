import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.dismiss) private var dismiss
    @State private var newStapleName = ""

    private var layout: [String] {
        StoreLayout.sanitized(store.state.currentStore.layout)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(store.state.currentStore.name)
                } header: {
                    Text("Laden")
                }

                Section {
                    ForEach(layout, id: \.self) { id in
                        layoutRow(id)
                    }
                } header: {
                    Text("Ladenweg")
                } footer: {
                    Text("Vor dem Einkauf immer vorn, Nach dem Einkauf immer hinten, Sonstiges direkt davor.")
                }

                Section {
                    let unused = StoreLayout.unused(in: layout)
                    if unused.isEmpty {
                        Text("Alle Abteilungen sind im Layout.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unused, id: \.self) { id in
                            Button(Department.title(for: id)) {
                                store.addLayoutDept(id)
                            }
                        }
                    }
                } header: {
                    Text("Abteilungen hinzufügen")
                }

                if store.state.currentStore.builtin {
                    Section {
                        Button("Layout zurücksetzen") {
                            store.resetLayout()
                        }
                    }
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
                } header: {
                    Text("Stamm-Artikel")
                } footer: {
                    Text("Stamm-Artikel erscheinen im Menü Stamm und können mit Gesamtliste auf einmal auf die Liste.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
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
        .foregroundStyle(locked ? Color.secondary : Color.primary)
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
}

#Preview {
    SettingsSheet()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
}
