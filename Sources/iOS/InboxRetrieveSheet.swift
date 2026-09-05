import SwiftUI

/// Auswahl der Inbox-Zeilen vor dem Import. Alle markiert; Abgewählte bleiben in `inbox.txt`.
struct InboxRetrieveSheet: View {
    let items: [String]
    let onConfirm: (Set<Int>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.einkaufTheme) private var theme
    @State private var selected: Set<Int>
    @State private var alertMessage: String?

    init(items: [String], onConfirm: @escaping (Set<Int>) -> Void) {
        self.items = items
        self.onConfirm = onConfirm
        _selected = State(initialValue: Set(items.indices))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items.indices, id: \.self) { index in
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
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .einkaufRowChrome()
                    .accessibilityLabel(items[index])
                    .accessibilityValue(selected.contains(index) ? "ausgewählt" : "abgewählt")
                    .accessibilityAddTraits(selected.contains(index) ? .isSelected : [])
                }
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

    private func confirm() {
        if selected.isEmpty {
            alertMessage = InboxParser.noneSelectedMessage()
            return
        }
        onConfirm(selected)
    }
}

#Preview {
    InboxRetrieveSheet(items: ["Milch", "Butter", "Eier"]) { _ in }
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
