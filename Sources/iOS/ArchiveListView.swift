import SwiftUI

/// Archiv-Einträge in **Einstellungen** (neueste zuerst). Wischen oder Papierkorb löscht einzeln.
struct ArchiveListView: View {
    enum Kind {
        case einkauf
        case todo
    }

    let kind: Kind
    @Environment(\.einkaufTheme) private var theme
    @State private var rows: [ArchiveDisplayRow] = []

    private var navigationTitle: String {
        switch kind {
        case .einkauf: return "Einkauf-Archiv"
        case .todo: return "To-Do-Archiv"
        }
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Text("Noch keine Archiv-Einträge.")
                    .foregroundStyle(theme.muted)
                    .einkaufRowChrome()
                    .deleteDisabled(true)
            } else {
                ForEach(rows) { row in
                    archiveRow(row)
                }
                .onDelete(perform: deleteDisplayed)
            }
        }
        .einkaufListChrome()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func archiveRow(_ row: ArchiveDisplayRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .foregroundStyle(theme.ink)
                Text(row.archivedAt)
                    .font(.footnote)
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) {
                deleteFileIndices(IndexSet(integer: row.fileIndex))
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Archiv-Eintrag löschen")
        }
        .einkaufRowChrome()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.archivedAt)")
    }

    private func reload() {
        switch kind {
        case .einkauf:
            let file = CompletedItemArchive.loadEinkauf()
            rows = CompletedItemArchive.displayRows(file.entries, title: { $0.name })
        case .todo:
            let file = CompletedItemArchive.loadTodo()
            rows = CompletedItemArchive.displayRows(file.entries, title: { $0.text })
        }
    }

    private func deleteDisplayed(at offsets: IndexSet) {
        let fileIndices = CompletedItemArchive.fileIndices(
            fromDisplayed: offsets,
            entryCount: rows.count
        )
        deleteFileIndices(fileIndices)
    }

    private func deleteFileIndices(_ indices: IndexSet) {
        switch kind {
        case .einkauf:
            CompletedItemArchive.deleteEinkauf(at: indices)
        case .todo:
            CompletedItemArchive.deleteTodo(at: indices)
        }
        reload()
    }
}
