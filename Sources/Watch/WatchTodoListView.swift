import SwiftUI

/// Geh-Modus: Text (+ kompakte Person/Prio/Datum/Abgeschlossen), Tippen toggelt `completed`.
/// Filtert auf die vom iPhone gesyncte aktuelle Liste (`todo.currentListId`).
/// Kein Edit, kein Prio-Picker, keine Ketten-UI, kein Import/Export, keine Suche, keine Listen-Verwaltung.
struct WatchTodoListView: View {
    @EnvironmentObject private var todos: TodoStore
    @Environment(\.einkaufTheme) private var theme
    /// Nur Watch-UserDefaults — nicht im Backup, nicht zum iPhone, nicht das Einkaufs-Watch-Auge.
    @AppStorage("todo.watch.hideCompleted") private var hideCompleted = false
    /// Vom iPhone per WC `currentListId` geschrieben (App-Group + Standard). Leer = Alle.
    @AppStorage("todo.currentListId") private var currentListId = ""

    private var listScopedTasks: [TodoTask] {
        TodoListFilter.tasks(todos.state.tasks, currentListId: currentListId)
    }

    private var visibleTasks: [TodoTask] {
        let source = hideCompleted ? listScopedTasks.filter { !$0.completed } : listScopedTasks
        return TodoOrdering.sorted(source)
    }

    private var titleLine: String {
        let name = TodoListFilter.title(lists: todos.state.lists, currentListId: currentListId)
        let counts = hideCompleted
            ? TodoListFilter.progressLabel(listScopedTasks.filter { !$0.completed })
            : TodoListFilter.progressLabel(listScopedTasks)
        return "\(name)  \(counts)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hideCompletedBar
                Text(titleLine)
                    .font(.caption)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .accessibilityLabel(titleLine)
                Group {
                    if todos.state.tasks.isEmpty {
                        Text("Noch nichts auf der Liste.")
                            .font(.headline)
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if !currentListId.isEmpty && listScopedTasks.isEmpty {
                        Text("Keine Aufgaben in dieser Liste.")
                            .font(.headline)
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else if visibleTasks.isEmpty {
                        Text("Erledigte ausgeblendet.")
                            .font(.headline)
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        List {
                            ForEach(visibleTasks) { task in
                                Button {
                                    todos.toggle(task.uid)
                                } label: {
                                    HStack(alignment: .center, spacing: 10) {
                                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                            .font(.title)
                                            .foregroundStyle(task.completed ? theme.good : theme.muted)
                                            .frame(width: 36, height: 36)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(task.text)
                                                .font(.headline)
                                                .foregroundStyle(theme.ink)
                                                .strikethrough(task.completed, color: theme.muted)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            metaLine(task)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                .listRowBackground(theme.paper2)
                                .accessibilityLabel(task.text)
                                .accessibilityValue(rowAccessibilityValue(task))
                            }
                        }
                        .einkaufListChrome()
                        .contentMargins(.top, 0, for: .scrollContent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .containerBackground(theme.paper, for: .navigation)
            .onAppear {
                todos.consumeSiriPendingAdds()
            }
        }
    }

    /// Chrome wie Einkauf-Watch: Nav-Bar ausgeblendet, Auge nicht in der Toolbar.
    private var hideCompletedBar: some View {
        HStack(spacing: 0) {
            Button {
                hideCompleted.toggle()
            } label: {
                Image(systemName: hideCompleted ? "eye.slash" : "eye")
                    .font(.caption)
                    .imageScale(.small)
                    .foregroundStyle(hideCompleted ? theme.muted : theme.good)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hideCompleted ? "Erledigte einblenden" : "Erledigte ausblenden")
            Spacer()
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private func metaLine(_ task: TodoTask) -> some View {
        let person = task.person.trimmingCharacters(in: .whitespacesAndNewlines)
        let prio = TodoJSON.prioA(task.prioA) + TodoJSON.prioB(task.prioB)
        let due = TodoJSON.isoDate(task.dueDate)
        let closed = TodoListGrouping.closedDateLabel(task)
        if !person.isEmpty || !prio.isEmpty || !due.isEmpty || !closed.isEmpty {
            HStack(spacing: 4) {
                if !person.isEmpty {
                    Text(person)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
                if !prio.isEmpty {
                    Text(prio)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
                if !due.isEmpty {
                    Text(TodoTime.displayDay(due))
                        .foregroundStyle(
                            TodoOrdering.isOverdue(due, today: TodoTime.localDayIso())
                                ? theme.oxide
                                : theme.muted
                        )
                        .lineLimit(1)
                }
                if !closed.isEmpty {
                    Text(closed)
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }
            .font(.caption2)
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
        let closed = TodoListGrouping.closedDateLabel(task)
        if !closed.isEmpty { parts.append(closed) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    WatchTodoListView()
        .environmentObject(TodoStore(state: .empty, enableSync: false))
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
