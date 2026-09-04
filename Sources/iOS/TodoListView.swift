import SwiftUI

/// iPhone-To-Do Phase 4: Person / Prio / Datum, Abgeschlossen-Toggle.
/// Backup: Phase 5. Watch: Phase 6.
struct TodoListView: View {
    @EnvironmentObject private var todos: TodoStore
    @Environment(\.einkaufTheme) private var theme
    @AppStorage("todo.iphone.showCompleted") private var showCompleted = true
    @State private var draft = ""
    @State private var draftPerson = ""
    @State private var draftPrioA = ""
    @State private var draftPrioB = ""
    @State private var draftDue = ""
    @State private var editingTask: TodoTask?

    private var visibleTasks: [TodoTask] {
        let source = showCompleted ? todos.state.tasks : todos.state.tasks.filter { !$0.completed }
        return TodoOrdering.sorted(source)
    }

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
                } else if visibleTasks.isEmpty {
                    ContentUnavailableView(
                        "Abgeschlossene ausgeblendet.",
                        systemImage: "eye.slash",
                        description: Text("Abgeschlossen einblenden, um erledigte Aufgaben zu sehen.")
                    )
                    .foregroundStyle(theme.ink)
                } else {
                    list
                }
            }
            .background(theme.paper)
            .navigationTitle("To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
            .sheet(item: $editingTask) { task in
                TodoEditSheet(task: task) { text, person, prioA, prioB, dueDate in
                    todos.update(task.uid, text: text, person: person, prioA: prioA, prioB: prioB, dueDate: dueDate)
                }
                .environment(\.einkaufTheme, theme)
                .einkaufScreen(theme)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Toggle("Abgeschlossen einblenden", isOn: $showCompleted)
                .accessibilityLabel("Abgeschlossen einblenden")
                .accessibilityValue(showCompleted ? "ein" : "aus")
        }
    }

    private var list: some View {
        List {
            ForEach(visibleTasks) { task in
                row(task)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .einkaufListChrome()
        .environment(\.editMode, .constant(.inactive))
    }

    private func row(_ task: TodoTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                todos.toggle(task.uid)
            } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.completed ? theme.good : theme.muted)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.completed ? "Erledigt: \(task.text)" : "Offen: \(task.text)")

            Button {
                editingTask = task
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .foregroundStyle(theme.ink)
                        .strikethrough(task.completed, color: theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    metaLine(task)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bearbeiten: \(task.text)")
        }
        .padding(.vertical, 2)
        .einkaufRowChrome()
        .accessibilityValue(rowAccessibilityValue(task))
    }

    @ViewBuilder
    private func metaLine(_ task: TodoTask) -> some View {
        let person = task.person.trimmingCharacters(in: .whitespacesAndNewlines)
        let prio = TodoJSON.prioA(task.prioA) + TodoJSON.prioB(task.prioB)
        let due = TodoJSON.isoDate(task.dueDate)
        if !person.isEmpty || !prio.isEmpty || !due.isEmpty {
            HStack(spacing: 6) {
                if !person.isEmpty {
                    Text(person)
                        .foregroundStyle(theme.muted)
                }
                if !prio.isEmpty {
                    Text(prio)
                        .foregroundStyle(theme.muted)
                }
                if !due.isEmpty {
                    Text(TodoTime.displayDay(due))
                        .foregroundStyle(
                            TodoOrdering.isOverdue(due, today: TodoTime.localDayIso())
                                ? theme.oxide
                                : theme.muted
                        )
                }
            }
            .font(.caption)
        }
    }

    private func rowAccessibilityValue(_ task: TodoTask) -> String {
        var parts = [task.completed ? "erledigt" : "offen"]
        let person = task.person.trimmingCharacters(in: .whitespacesAndNewlines)
        if !person.isEmpty { parts.append(person) }
        let prio = TodoJSON.prioA(task.prioA) + TodoJSON.prioB(task.prioB)
        if !prio.isEmpty { parts.append(prio) }
        let due = TodoJSON.isoDate(task.dueDate)
        if !due.isEmpty {
            let label = TodoTime.displayDay(due)
            if TodoOrdering.isOverdue(due, today: TodoTime.localDayIso()) {
                parts.append("überfällig \(label)")
            } else {
                parts.append(label)
            }
        }
        return parts.joined(separator: ", ")
    }

    private var addBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Person", text: $draftPerson)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .accessibilityLabel("Person")
                TodoPrioPickers(prioA: $draftPrioA, prioB: $draftPrioB)
                TodoDuePicker(iso: $draftDue)
            }
            HStack(spacing: 8) {
                TextField("Neue Aufgabe …", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(submit)
                Button("Hinzufügen", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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
        todos.add(draft, person: draftPerson, prioA: draftPrioA, prioB: draftPrioB, dueDate: draftDue)
        draft = ""
        draftPerson = ""
        draftPrioA = ""
        draftPrioB = ""
        draftDue = ""
    }

    private func delete(_ offsets: IndexSet) {
        let uids = offsets.compactMap { index -> Int64? in
            visibleTasks.indices.contains(index) ? visibleTasks[index].uid : nil
        }
        for uid in uids {
            todos.delete(uid)
        }
    }
}

private struct TodoPrioPickers: View {
    @Binding var prioA: String
    @Binding var prioB: String

    var body: some View {
        HStack(spacing: 4) {
            Picker("Prio A", selection: $prioA) {
                Text("– Prio").tag("")
                ForEach(TodoJSON.prioAChoices, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Prio A")
            Picker("Prio B", selection: $prioB) {
                Text("–").tag("")
                ForEach(TodoJSON.prioBChoices, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Prio B")
        }
        .fixedSize()
    }
}

private struct TodoDuePicker: View {
    @Binding var iso: String
    @Environment(\.einkaufTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            if iso.isEmpty {
                Button("Datum") {
                    iso = TodoTime.localDayIso()
                }
                .foregroundStyle(theme.muted)
                .accessibilityLabel("Datum setzen")
            } else {
                DatePicker(
                    "Enddatum",
                    selection: Binding(
                        get: { TodoTime.date(fromLocalDay: iso) ?? Date() },
                        set: { iso = TodoTime.localDayIso($0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .accessibilityLabel("Enddatum")
                Button {
                    iso = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.muted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Datum löschen")
            }
        }
        .fixedSize()
    }
}

private struct TodoEditSheet: View {
    let task: TodoTask
    var onSave: (_ text: String, _ person: String, _ prioA: String, _ prioB: String, _ dueDate: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.einkaufTheme) private var theme
    @State private var text: String
    @State private var person: String
    @State private var prioA: String
    @State private var prioB: String
    @State private var dueDate: String

    init(
        task: TodoTask,
        onSave: @escaping (_ text: String, _ person: String, _ prioA: String, _ prioB: String, _ dueDate: String) -> Void
    ) {
        self.task = task
        self.onSave = onSave
        _text = State(initialValue: task.text)
        _person = State(initialValue: task.person)
        _prioA = State(initialValue: TodoJSON.prioA(task.prioA))
        _prioB = State(initialValue: TodoJSON.prioB(task.prioB))
        _dueDate = State(initialValue: TodoJSON.isoDate(task.dueDate))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Aufgabe", text: $text)
                        .einkaufRowChrome()
                    TextField("Person", text: $person)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .einkaufRowChrome()
                    HStack {
                        Text("Prio")
                            .foregroundStyle(theme.muted)
                        Spacer()
                        TodoPrioPickers(prioA: $prioA, prioB: $prioB)
                    }
                    .einkaufRowChrome()
                    HStack {
                        Text("Datum")
                            .foregroundStyle(theme.muted)
                        Spacer()
                        TodoDuePicker(iso: $dueDate)
                    }
                    .einkaufRowChrome()
                }
            }
            .listStyle(.insetGrouped)
            .einkaufListChrome()
            .navigationTitle("Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        onSave(text, person, prioA, prioB, dueDate)
        dismiss()
    }
}

#Preview {
    TodoListView()
        .environmentObject(TodoStore(state: .empty, enableSync: false))
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
