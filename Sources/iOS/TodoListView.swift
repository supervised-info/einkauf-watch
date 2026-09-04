import SwiftUI

/// iPhone-To-Do v1: Text anlegen, abhaken, löschen, umbenennen.
/// Person / Prio / Datum: Phase 4. Backup: Phase 5. Watch: Phase 6.
struct TodoListView: View {
    @EnvironmentObject private var todos: TodoStore
    @Environment(\.einkaufTheme) private var theme
    @State private var draft = ""
    @State private var renamingUID: Int64?
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if todos.state.tasks.isEmpty {
                    ContentUnavailableView(
                        "Noch nichts auf der Liste.",
                        systemImage: "checklist",
                        description: Text("Aufgabe hinzufügen.")
                    )
                    .foregroundStyle(theme.ink)
                } else {
                    list
                }
            }
            .background(theme.paper)
            .navigationTitle("To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
        }
    }

    private var list: some View {
        List {
            ForEach(todos.state.tasks) { task in
                row(task)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .einkaufListChrome()
        .environment(\.editMode, .constant(.inactive))
    }

    private func row(_ task: TodoTask) -> some View {
        HStack(spacing: 10) {
            Button {
                commitRename()
                todos.toggle(task.uid)
            } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.completed ? theme.good : theme.muted)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.completed ? "Erledigt: \(task.text)" : "Offen: \(task.text)")

            if renamingUID == task.uid {
                TextField("Aufgabe", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .submitLabel(.done)
                    .onSubmit(commitRename)
                    .onChange(of: renameFocused) { _, focused in
                        if !focused { commitRename() }
                    }
                    .strikethrough(task.completed, color: theme.muted)
            } else {
                Button {
                    beginRename(task)
                } label: {
                    Text(task.text)
                        .foregroundStyle(theme.ink)
                        .strikethrough(task.completed, color: theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Umbenennen: \(task.text)")
            }
        }
        .padding(.vertical, 2)
        .einkaufRowChrome()
        .accessibilityValue(task.completed ? "erledigt" : "offen")
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("Neue Aufgabe …", text: $draft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(submit)
            Button("Hinzufügen", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.paper2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.rule)
                .frame(height: 1)
        }
    }

    private func submit() {
        commitRename()
        todos.add(draft)
        draft = ""
    }

    private func delete(_ offsets: IndexSet) {
        commitRename()
        let uids = offsets.compactMap { index -> Int64? in
            todos.state.tasks.indices.contains(index) ? todos.state.tasks[index].uid : nil
        }
        for uid in uids {
            todos.delete(uid)
        }
    }

    private func beginRename(_ task: TodoTask) {
        renamingUID = task.uid
        renameDraft = task.text
        renameFocused = true
    }

    private func commitRename() {
        guard let uid = renamingUID else { return }
        todos.update(uid, text: renameDraft)
        renamingUID = nil
        renameFocused = false
        renameDraft = ""
    }
}

#Preview {
    TodoListView()
        .environmentObject(TodoStore(state: .empty, enableSync: false))
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
