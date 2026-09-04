import SwiftUI
import UniformTypeIdentifiers

/// iPhone-To-Do: Person / Prio / Datum, Wieder öffnen, Sort, Suche, Backup `todo-v3-json`, Liste teilen (PDF).
/// Watch: nur Liste + Toggle, ohne Reopen/Suche/Sort-UI.
struct TodoListView: View {
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.einkaufTheme) private var theme
    @AppStorage("todo.iphone.showCompleted") private var showCompleted = true
    @AppStorage("todo.iphone.sortKey") private var sortKeyRaw = TodoSortKey.person.rawValue
    @State private var draft = ""
    @State private var draftPerson = ""
    @State private var draftPrioA = ""
    @State private var draftPrioB = ""
    @State private var draftDue = ""
    @State private var isEditing = false
    @State private var editingTask: TodoTask?
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = BackupFileDocument(data: Data())
    @State private var shareItem: BackupShareItem?
    @State private var alertMessage: String?
    @State private var pendingImport: Data?
    @State private var showImportChoice = false
    @State private var importSummary = ""
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var pendingReopen: TodoTask?
    @State private var highlightUid: Int64?
    @State private var scrollToUid: Int64?

    private var sortKey: TodoSortKey {
        TodoSortKey(rawValue: sortKeyRaw) ?? .person
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleTasks: [TodoTask] {
        var source = showCompleted ? todos.state.tasks : todos.state.tasks.filter { !$0.completed }
        if !searchQuery.isEmpty {
            source = source.filter { TodoOrdering.matches($0, query: searchQuery) }
        }
        return TodoOrdering.sorted(source, by: sortKey)
    }

    var body: some View {
        NavigationStack {
            Group {
                if todos.state.tasks.isEmpty {
                    ContentUnavailableView(
                        "Noch nichts auf der Liste.",
                        systemImage: "checklist",
                        description: Text("Aufgabe hinzufügen oder ein Backup importieren.")
                    )
                    .foregroundStyle(theme.ink)
                } else if visibleTasks.isEmpty {
                    if !searchQuery.isEmpty {
                        ContentUnavailableView(
                            "Keine Treffer.",
                            systemImage: "magnifyingglass",
                            description: Text("Person oder Text ändern.")
                        )
                        .foregroundStyle(theme.ink)
                    } else {
                        ContentUnavailableView(
                            "Abgeschlossene ausgeblendet.",
                            systemImage: "eye.slash",
                            description: Text("Abgeschlossen einblenden, um erledigte Aufgaben zu sehen.")
                        )
                        .foregroundStyle(theme.ink)
                    }
                } else {
                    list
                }
            }
            .background(theme.paper)
            .navigationTitle("To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .top, spacing: 0) { searchBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "todo-liste") { result in
                if case .failure(let error) = result {
                    alertMessage = error.localizedDescription
                }
            }
            .alert("Hinweis", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("To-Do importieren", isPresented: $showImportChoice, titleVisibility: .visible) {
                Button("Anhängen") { commitPending(append: true) }
                Button("Ersetzen") { commitPending(append: false) }
                Button("Abbrechen", role: .cancel) { pendingImport = nil }
            } message: {
                Text(importSummary)
            }
            .background {
                Color.clear
                    .confirmationDialog(
                        "Wieder öffnen",
                        isPresented: Binding(
                            get: { pendingReopen != nil },
                            set: { if !$0 { pendingReopen = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button("Fortfahren") { confirmReopen() }
                        Button("Abbrechen", role: .cancel) { pendingReopen = nil }
                    } message: {
                        if let task = pendingReopen {
                            Text("Aufgabe #\(task.uid) bleibt abgeschlossen. Eine neue offene Kopie wird erstellt. Fortfahren?")
                        }
                    }
            }
            .onChange(of: todos.lastError) { _, new in
                if let new { alertMessage = new }
            }
            .onChange(of: isSearching) { _, open in
                if open { searchFocused = true }
            }
            .onKeyPress(.escape) {
                if isSearching {
                    closeSearch()
                    return .handled
                }
                return .ignored
            }
            .sheet(item: $editingTask) { task in
                TodoEditSheet(
                    task: task,
                    onSave: { text, person, prioA, prioB, dueDate in
                        todos.update(task.uid, text: text, person: person, prioA: prioA, prioB: prioB, dueDate: dueDate)
                    },
                    onReopen: {
                        pendingReopen = task
                    }
                )
                .environment(\.einkaufTheme, theme)
                .einkaufScreen(theme)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if isSearching {
                    closeSearch()
                } else {
                    isSearching = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .symbolVariant(isSearching || !searchQuery.isEmpty ? .fill : .none)
            }
            .accessibilityLabel(isSearching ? "Suche schließen" : "Suche")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showCompleted.toggle()
            } label: {
                Image(systemName: showCompleted ? "eye" : "eye.slash")
            }
            .accessibilityLabel(showCompleted ? "Abgeschlossene ausblenden" : "Abgeschlossene einblenden")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(isEditing ? "Fertig" : "Bearbeiten") {
                isEditing.toggle()
            }
            .accessibilityLabel(isEditing ? "Fertig" : "Bearbeiten")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sortierung", selection: $sortKeyRaw) {
                    ForEach(TodoSortKey.allCases, id: \.rawValue) { key in
                        Text(key.menuTitle).tag(key.rawValue)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sortierung")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Backup importieren…", systemImage: "square.and.arrow.down") {
                    showImporter = true
                }
                Button("Backup exportieren…", systemImage: "square.and.arrow.up") {
                    exportBackup()
                }
                Button("Backup teilen", systemImage: "square.and.arrow.up.on.square") {
                    shareBackup()
                }
                Button("Liste teilen", systemImage: "list.bullet.rectangle") {
                    shareList()
                }
                Button("Erledigte löschen", systemImage: "trash") {
                    todos.clearCompleted()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Mehr")
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        if isSearching {
            HStack(spacing: 8) {
                TextField("Person oder Text …", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .accessibilityLabel("Person oder Text")
                    .onSubmit {
                        if searchQuery.isEmpty { closeSearch() }
                    }
                    .onChange(of: searchFocused) { _, focused in
                        if !focused && searchQuery.isEmpty {
                            isSearching = false
                        }
                    }
                Button(action: closeSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.muted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Suche schließen")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.paper2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.rule)
                    .frame(height: 1)
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            Group {
                if isEditing {
                    editingList
                } else {
                    browsingList
                }
            }
            .id(isEditing ? "todo-edit" : "todo-browse")
            .onChange(of: scrollToUid) { _, uid in
                guard let uid else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(uid, anchor: .center) }
                }
            }
        }
    }

    /// Listen-Modus: kein Swipe-Löschen. Trailing-`EmptyView` ersetzt das System-Delete,
    /// das SwiftUI sonst neben Leading-„Bearbeiten“ einblendet. `.id("todo-browse")`
    /// verhindert, dass Bearbeiten-Zeilen (mit `.onDelete`) wiederverwendet werden.
    private var browsingList: some View {
        List {
            ForEach(visibleTasks) { task in
                row(task)
                    .id(task.uid)
                    .listRowBackground(highlightUid == task.uid ? theme.oxide.opacity(0.22) : nil)
                    .deleteDisabled(true)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        EmptyView()
                    }
            }
        }
        .listStyle(.insetGrouped)
        .einkaufListChrome()
        .environment(\.editMode, .constant(.inactive))
        .id("todo-browse")
    }

    /// Bearbeiten: Swipe-Löschen nur hier, über `.onDelete`.
    private var editingList: some View {
        List {
            ForEach(visibleTasks) { task in
                row(task)
                    .id(task.uid)
                    .listRowBackground(highlightUid == task.uid ? theme.oxide.opacity(0.22) : nil)
                    .deleteDisabled(false)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
        .einkaufListChrome()
        .environment(\.editMode, .constant(.inactive))
        .id("todo-edit")
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

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    editingTask = task
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.text)
                                .foregroundStyle(theme.ink)
                                .strikethrough(task.completed, color: theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            metaLine(task)
                        }
                        if isEditing {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(theme.muted)
                                .padding(.top, 4)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bearbeiten: \(task.text)")
                chainHint(task)
            }
        }
        .padding(.vertical, 2)
        .einkaufRowChrome()
        .accessibilityValue(rowAccessibilityValue(task))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editingTask = task
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            if TodoOrdering.canReopen(task) {
                Button {
                    pendingReopen = task
                } label: {
                    Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                }
                .tint(theme.oxide)
            }
        }
        .contextMenu {
            Button {
                editingTask = task
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            if TodoOrdering.canReopen(task) {
                Button {
                    pendingReopen = task
                } label: {
                    Label("Wieder öffnen", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    @ViewBuilder
    private func chainHint(_ task: TodoTask) -> some View {
        let from = task.reopenedFromUid
        let to = task.reopenedToUid
        if from != nil || to != nil {
            HStack(spacing: 8) {
                if let from {
                    Button {
                        revealAndScroll(to: from)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("von #\(from)")
                        }
                    }
                    .accessibilityLabel("Wiederaufnahme von Aufgabe \(from)")
                }
                if let to {
                    Button {
                        revealAndScroll(to: to)
                    } label: {
                        HStack(spacing: 2) {
                            Text("→ #\(to)")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .accessibilityLabel("Wieder geöffnet als Aufgabe \(to)")
                }
            }
            .font(.caption)
            .foregroundStyle(theme.muted)
            .buttonStyle(.borderless)
        }
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
        if let from = task.reopenedFromUid {
            parts.append("von \(from)")
        }
        if let to = task.reopenedToUid {
            parts.append("wieder geöffnet als \(to)")
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

    private func closeSearch() {
        searchText = ""
        isSearching = false
        searchFocused = false
    }

    private func confirmReopen() {
        guard let task = pendingReopen else { return }
        pendingReopen = nil
        guard let newUid = todos.reopen(task.uid) else { return }
        flash(newUid)
    }

    private func revealAndScroll(to uid: Int64) {
        if let related = todos.state.tasks.first(where: { $0.uid == uid }), related.completed {
            showCompleted = true
        }
        flash(uid)
    }

    private func flash(_ uid: Int64) {
        highlightUid = uid
        scrollToUid = uid
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if highlightUid == uid { highlightUid = nil }
            if scrollToUid == uid { scrollToUid = nil }
        }
    }

    private func delete(_ offsets: IndexSet) {
        let uids = offsets.compactMap { index -> Int64? in
            visibleTasks.indices.contains(index) ? visibleTasks[index].uid : nil
        }
        for uid in uids {
            todos.delete(uid)
        }
    }

    private func exportBackup() {
        do {
            exportDocument = BackupFileDocument(data: try todos.exportBackup())
            showExporter = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareBackup() {
        do {
            let data = try todos.exportBackup()
            let url = try BackupShare.writeTempFile(data: data, stem: BackupShare.todoStem)
            guard FileManager.default.fileExists(atPath: url.path) else {
                alertMessage = "Backup-Datei konnte nicht erzeugt werden."
                return
            }
            shareItem = BackupShareItem(url: url)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareList() {
        let groups = TodoListGrouping.groups(todos.state.tasks, showCompleted: showCompleted)
        guard !groups.isEmpty else {
            if todos.state.tasks.isEmpty {
                alertMessage = "Die Liste ist leer."
            } else {
                alertMessage = "Keine offenen Aufgaben. Abgeschlossene sind ausgeblendet."
            }
            return
        }
        do {
            let data = try TodoListPDF.render(
                groups: groups,
                progressLabel: TodoListGrouping.progressLabel(groups: groups),
                colors: ThemeRGB.tokens(palette: appearance.palette, dark: false)
            )
            let url = try ListShare.writeTodoTempFile(data: data)
            guard FileManager.default.fileExists(atPath: url.path) else {
                alertMessage = "PDF-Datei konnte nicht erzeugt werden."
                return
            }
            shareItem = BackupShareItem(url: url)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try IncomingJSON.data(from: url)
                try offerOrApply(data)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func offerOrApply(_ data: Data) throws {
        switch IncomingJSON.classify(data) {
        case .todoBackup:
            break
        case .einkaufBackup:
            throw TodoCodecError.einkaufFile
        case .invalidJSON:
            throw IncomingJSONError.invalidJSON
        case .unknown:
            throw IncomingJSONError.unknownFormat
        }
        let incoming = try TodoCodec.decodeBackup(data)
        if todos.state.tasks.isEmpty {
            try todos.importBackup(data, append: false)
            return
        }
        pendingImport = data
        importSummary = TodoImportPrompt.message(
            currentCount: todos.state.tasks.count,
            incomingCount: incoming.tasks.count
        )
        showImportChoice = true
    }

    private func commitPending(append: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            try todos.importBackup(data, append: append)
        } catch {
            alertMessage = error.localizedDescription
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
    var onReopen: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.einkaufTheme) private var theme
    @State private var text: String
    @State private var person: String
    @State private var prioA: String
    @State private var prioB: String
    @State private var dueDate: String

    init(
        task: TodoTask,
        onSave: @escaping (_ text: String, _ person: String, _ prioA: String, _ prioB: String, _ dueDate: String) -> Void,
        onReopen: (() -> Void)? = nil
    ) {
        self.task = task
        self.onSave = onSave
        self.onReopen = onReopen
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
                if onReopen != nil, TodoOrdering.canReopen(task) {
                    Section {
                        Button("Wieder öffnen") {
                            onReopen?()
                            dismiss()
                        }
                    }
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
        .environmentObject(AppearanceSettings())
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
