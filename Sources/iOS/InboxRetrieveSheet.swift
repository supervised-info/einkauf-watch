import SwiftUI

/// Auswahl der Inbox-Zeilen vor dem Import. Alle markiert; Abgewählte bleiben in `inbox.txt`.
/// **Löschen** schreibt die Datei sofort ohne Import; die Sheet-Liste folgt nach.
struct InboxRetrieveSheet: View {
    let onConfirm: (Set<Int>) -> Void
    let onDeleteRemaining: ([String]) -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.einkaufTheme) private var theme
    @State private var items: [String]
    @State private var selected: Set<Int>
    @State private var alertMessage: String?

    init(
        items: [String],
        onConfirm: @escaping (Set<Int>) -> Void,
        onDeleteRemaining: @escaping ([String]) -> String?
    ) {
        self.onConfirm = onConfirm
        self.onDeleteRemaining = onDeleteRemaining
        _items = State(initialValue: items)
        _selected = State(initialValue: Set(items.indices))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Button {
                            toggle(index)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selected.contains(index) ? theme.good : theme.muted)
                                Text(items[index])
                                    .foregroundStyle(theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(items[index])
                        .accessibilityValue(selected.contains(index) ? "ausgewählt" : "abgewählt")
                        .accessibilityAddTraits(selected.contains(index) ? .isSelected : [])

                        Button(role: .destructive) {
                            deleteItems(at: IndexSet(integer: index))
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Löschen")
                    }
                    .padding(.vertical, 4)
                    .einkaufRowChrome()
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.insetGrouped)
            .einkaufListChrome()
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { confirm() }
                }
            }
            .alert("Hinweis", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let deleted = Set(offsets)
        let remaining = InboxParser.removing(items: items, at: deleted)
        if let error = onDeleteRemaining(remaining) {
            alertMessage = error
            return
        }
        selected = InboxParser.shiftingSelection(selected, removing: deleted)
        items = remaining
        if items.isEmpty {
            dismiss()
        }
    }

    private func confirm() {
        if selected.isEmpty {
            alertMessage = InboxParser.noneSelectedMessage()
            return
        }
        onConfirm(selected)
    }
}

#Preview {
    InboxRetrieveSheet(items: ["Milch", "Butter", "Eier"], onConfirm: { _ in }, onDeleteRemaining: { _ in nil })
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
