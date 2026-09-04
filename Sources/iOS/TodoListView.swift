import SwiftUI
import UniformTypeIdentifiers

/// iPhone-To-Do: Person / Prio / Datum, Wieder öffnen, Sort, Suche, benannte Listen,
/// Backup `todo-v3-json`, MD/CSV (volle Liste), Liste teilen (PDF folgt Liste + Auge).
/// Watch: nur Liste + Toggle, ohne Reopen/Suche/Sort/MD/CSV/Listen-UI.
struct TodoListView: View {
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.einkaufTheme) private var theme
    @AppStorage("todo.iphone.showCompleted") private var showCompleted = true
    @AppStorage("todo.iphone.sortKey") private var sortKeyRaw = TodoSortKey.person.rawValue
    /// Leer = Alle (ungefiltert). Nicht im Backup.
    @AppStorage("todo.iphone.currentListId") private var currentListId = ""
    @State private var draft = ""
    @State private var draftPerson = ""
    @State private var draftPrioA = ""
    @State private var draftPrioB = ""
    @State private var draftDue = ""
    @State private var isEditing = false
    @State private var editingTask: TodoTask?
    @State private var showImporter = false
    @State private var showJSONExporter = false
    @State private var showMDExporter = false
    @State private var showCSVExporter = false
    @State private var exportDocument = TodoFileDocument(data: Data())
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
    @State private var showCreateList = false
    @State private var showManageLists = false
    @State private var newListName = ""

    private var sortKey: TodoSortKey {
        TodoSortKey(rawValue: sortKeyRaw) ?? .person
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var listScopedTasks: [TodoTask] {
        TodoListFilter.tasks(todos.state.tasks, currentListId: currentListId)
    }

    private var countTasks: [TodoTask] {
        showCompleted ? listScopedTasks : listScopedTasks.filter { !$0.completed }
    }

    private var progressLabel: String {
        TodoListFilter.progressLabel(countTasks)
    }

    private var currentListTitle: String {
        TodoListFilter.title(lists: todos.state.lists, currentListId: currentListId)
    }

    private var visibleTasks: [TodoTask] {
        var source = countTasks
        if !searchQuery.isEmpty {
            source = source.filter { TodoOrdering.matches($0, query: searchQuery) }
        }
        return TodoOrdering.sorted(source, by: sortKey)
    }

    var body: some View {
        NavigationStack {
            withSheets(withDialogs(withTransfers(chrome)))
        }
    }

    /// Chrome ohne Importer/Sheets — eigener Typ, damit `body` type-checkt.
    private var chrome: some View {
        mainContent
            .background(theme.paper)
            .navigationTitle("To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .top, spacing: 0) { searchBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
    }

    @ViewBuilder
    private var mainContent: some View {
        if todos.state.tasks.isEmpty {
            emptyNoTasks
        } else if visibleTasks.isEmpty {
            emptyFiltered
        } else {
            list
        }
    }

    private var emptyNoTasks: some View {
        emptyState(
            "Noch nichts auf der Liste.",
            systemImage: "checklist",
            description: "Aufgabe hinzufügen oder ein Backup importieren."
        )
    }

    @ViewBuilder
    private var emptyFiltered: some View {
        if !searchQuery.isEmpty {
            emptySearch
        } else if !currentListId.isEmpty && listScopedTasks.isEmpty {
            emptyNamedList
        } else {
            emptyHiddenCompleted
        }
    }

    private var emptySearch: some View {
        emptyState(
            "Keine Treffer.",
            systemImage: "magnifyingglass",
            description: "Person oder Text ändern."
        )
    }

    private var emptyNamedList: some View {
        emptyState(
            "Keine Aufgaben in dieser Liste.",
            systemImage: "checklist",
            description: "Aufgabe hinzufügen oder eine andere Liste wählen."
        )
    }

    private var emptyHiddenCompleted: some View {
        emptyState(
            "Abgeschlossene ausgeblendet.",
            systemImage: "eye.slash",
            description: "Abgeschlossen einblenden, um erledigte Aufgaben zu sehen."
        )
    }

    private func emptyState(_ title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .foregroundStyle(theme.ink)
    }

    private func withTransfers<Content: View>(_ content: Content) -> some View {
        withCSVExport(withMDExport(withJSONExport(withImport(content))))
    }

    private func withImport<Content: View>(_ content: Content) -> some View {
        content.fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: TodoImportUTTypes.all,
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func withJSONExport<Content: View>(_ content: Content) -> some View {
        content.fileExporter(
            isPresented: $showJSONExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "todo-liste"
        ) { result in
            handleExportResult(result)
        }
    }

    private func withMDExport<Content: View>(_ content: Content) -> some View {
        content.fileExporter(
            isPresented: $showMDExporter,
            document: exportDocument,
            contentType: TodoFileDocument.markdownType,
            defaultFilename: "todo-liste"
        ) { result in
            handleExportResult(result)
        }
    }

    private func withCSVExport<Content: View>(_ content: Content) -> some View {
        content.fileExporter(
            isPresented: $showCSVExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "todo-liste"
        ) { result in
            handleExportResult(result)
        }
    }

    private func withDialogs<Content: View>(_ content: Content) -> some View {
        withListObservers(withImportChoice(withHintAlert(content)))
    }

    private func withHintAlert<Content: View>(_ content: Content) -> some View {
        content.alert("Hinweis", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func withImportChoice<Content: View>(_ content: Content) -> some View {
        content
            .confirmationDialog("To-Do importieren", isPresented: $showImportChoice, titleVisibility: .visible) {
                Button("Anhängen") { commitPending(append: true) }
                Button("Ersetzen") { commitPending(append: false) }
                Button("Abbrechen", role: .cancel) { pendingImport = nil }
            } message: {
                Text(importSummary)
            }
            .background { reopenDialog }
    }

    private func withListObservers<Content: View>(_ content: Content) -> some View {
        content
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
            .onChange(of: currentListId) { _, id in
                if !id.isEmpty && todos.state.list(id: id) == nil {
                    currentListId = ""
                }
                todos.broadcastCurrentList()
            }
    }

    private var reopenDialog: some View {
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

    private func withSheets<Content: View>(_ content: Content) -> some View {
        withShareSheet(withEditSheet(withListSheets(content)))
    }

    private func withListSheets<Content: View>(_ content: Content) -> some View {
        content
            .alert("Neue Liste", isPresented: $showCreateList) {
                TextField("Name", text: $newListName)
                Button("Anlegen") { createList() }
                Button("Abbrechen", role: .cancel) { newListName = "" }
            } message: {
                Text("Aufgaben dieser Liste erscheinen, wenn sie ausgewählt ist.")
            }
            .sheet(isPresented: $showManageLists) {
                manageListsSheet
            }
    }

    private func withEditSheet<Content: View>(_ content: Content) -> some View {
        content.sheet(item: $editingTask) { task in
            editTaskSheet(task)
        }
    }

    private func withShareSheet<Content: View>(_ content: Content) -> some View {
        content.sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
                .ignoresSafeArea()
        }
    }

    private var manageListsSheet: some View {
        TodoListsSheet(
            lists: todos.state.lists,
            onRename: { id, name in todos.renameList(id: id, name: name) },
            onDelete: { list in
                todos.deleteList(id: list.id)
                if currentListId == list.id {
                    currentListId = ""
                }
            }
        )
        .environment(\.einkaufTheme, theme)
        .einkaufScreen(theme)
    }

    private func editTaskSheet(_ task: TodoTask) -> some View {
        TodoEditSheet(
            task: task,
            lists: todos.state.lists,
            onSave: { text, person, prioA, prioB, dueDate, listId in
                todos.update(
                    task.uid,
                    text: text,
                    person: person,
                    prioA: prioA,
                    prioB: prioB,
                    dueDate: dueDate,
                    listId: .some(listId)
                )
            },
            onReopen: {
                pendingReopen = task
            }
        )
        .environment(\.einkaufTheme, theme)
        .einkaufScreen(theme)
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
        ToolbarItem(placement: .topBarLeading) {
            listFilterMenu
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
            Button(isEditing ? "Fertig" : "Edit") {
                isEditing.toggle()
            }
            .accessibilityLabel(isEditing ? "Fertig" : "Edit")
        }
        ToolbarItem(placement: .topBarTrailing) {
            sortMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            overflowMenu
        }
    }

    private var listFilterMenu: some View {
        Menu {
            Button {
                currentListId = ""
            } label: {
                if currentListId.isEmpty {
                    Label(TodoListFilter.allTitle, systemImage: "checkmark")
                } else {
                    Text(TodoListFilter.allTitle)
                }
            }
            ForEach(todos.state.lists) { list in
                Button {
                    currentListId = list.id
                } label: {
                    if currentListId == list.id {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
            Divider()
            Button("Neue Liste…", systemImage: "plus") {
                newListName = ""
                showCreateList = true
            }
            Button("Listen…", systemImage: "pencil") {
                showManageLists = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text(currentListTitle)
            }
        }
        .accessibilityLabel("Liste")
        .accessibilityValue("\(currentListTitle), \(progressLabel)")
    }

    private var sortMenu: some View {
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

    private var overflowMenu: some View {
        Menu {
            Button("Backup importieren…", systemImage: "square.and.arrow.down") {
                showImporter = true
            }
            Button("Backup exportieren…", systemImage: "square.and.arrow.up") {
                exportJSON()
            }
            Button("Backup teilen", systemImage: "square.and.arrow.up.on.square") {
                shareJSON()
            }
            Button("MD exportieren…", systemImage: "doc.richtext") {
                exportMarkdown()
            }
            Button("MD teilen", systemImage: "square.and.arrow.up.on.square") {
                shareMarkdown()
            }
            Button("CSV exportieren…", systemImage: "tablecells") {
                exportCSV()
            }
            Button("CSV teilen", systemImage: "square.and.arrow.up.on.square") {
                shareCSV()
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
    /// das SwiftUI sonst neben Leading-„Edit“ einblendet. `.id("todo-browse")`
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
                .accessibilityLabel("Edit: \(task.text)")
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
                Label("Edit", systemImage: "pencil")
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
                Label("Edit", systemImage: "pencil")
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

    private func createList() {
        let name = newListName
        newListName = ""
        guard let id = todos.addList(name: name) else { return }
        currentListId = id
    }

    private func submit() {
        todos.add(
            draft,
            person: draftPerson,
            prioA: draftPrioA,
            prioB: draftPrioB,
            dueDate: draftDue,
            listId: TodoJSON.normalizedListId(currentListId)
        )
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

    private func handleExportResult(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            alertMessage = error.localizedDescription
        }
    }

    private func exportJSON() {
        do {
            exportDocument = TodoFileDocument(data: try todos.exportBackup())
            showJSONExporter = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareJSON() {
        shareData(
            { try todos.exportBackup() },
            ext: "json",
            missing: "Backup-Datei konnte nicht erzeugt werden."
        )
    }

    /// Volle Liste aller Aufgaben und Listen, unabhängig vom Auge und vom Listenfilter — Roundtrip.
    private func exportMarkdown() {
        do {
            exportDocument = TodoFileDocument(data: try todos.exportMarkdown())
            showMDExporter = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareMarkdown() {
        shareData(
            { try todos.exportMarkdown() },
            ext: "md",
            missing: "Markdown-Datei konnte nicht erzeugt werden."
        )
    }

    /// Volle Liste, unabhängig vom Auge — Roundtrip mit HTML.
    private func exportCSV() {
        do {
            exportDocument = TodoFileDocument(data: try todos.exportCSV())
            showCSVExporter = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareCSV() {
        shareData(
            { try todos.exportCSV() },
            ext: "csv",
            missing: "CSV-Datei konnte nicht erzeugt werden."
        )
    }

    private func shareData(_ make: () throws -> Data, ext: String, missing: String) {
        do {
            let data = try make()
            let url = try BackupShare.writeTempFile(data: data, stem: BackupShare.todoStem, ext: ext)
            guard FileManager.default.fileExists(atPath: url.path) else {
                alertMessage = missing
                return
            }
            shareItem = BackupShareItem(url: url)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareList() {
        let groups = TodoListGrouping.groups(
            todos.state.tasks,
            showCompleted: showCompleted,
            currentListId: currentListId
        )
        guard !groups.isEmpty else {
            if todos.state.tasks.isEmpty {
                alertMessage = "Die Liste ist leer."
            } else if listScopedTasks.isEmpty {
                alertMessage = "Keine Aufgaben in dieser Liste."
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
        let incoming = try TodoImport.decode(data)
        if todos.state.tasks.isEmpty {
            try todos.importAny(data, append: false)
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
            try todos.importAny(data, append: append)
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
    let lists: [TodoNamedList]
    var onSave: (_ text: String, _ person: String, _ prioA: String, _ prioB: String, _ dueDate: String, _ listId: String?) -> Void
    var onReopen: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.einkaufTheme) private var theme
    @State private var text: String
    @State private var person: String
    @State private var prioA: String
    @State private var prioB: String
    @State private var dueDate: String
    @State private var listId: String

    init(
        task: TodoTask,
        lists: [TodoNamedList] = [],
        onSave: @escaping (_ text: String, _ person: String, _ prioA: String, _ prioB: String, _ dueDate: String, _ listId: String?) -> Void,
        onReopen: (() -> Void)? = nil
    ) {
        self.task = task
        self.lists = lists
        self.onSave = onSave
        self.onReopen = onReopen
        _text = State(initialValue: task.text)
        _person = State(initialValue: task.person)
        _prioA = State(initialValue: TodoJSON.prioA(task.prioA))
        _prioB = State(initialValue: TodoJSON.prioB(task.prioB))
        _dueDate = State(initialValue: TodoJSON.isoDate(task.dueDate))
        _listId = State(initialValue: TodoJSON.normalizedListId(task.listId) ?? "")
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
                    HStack {
                        Text("Liste")
                            .foregroundStyle(theme.muted)
                        Spacer()
                        Picker("Liste", selection: $listId) {
                            Text(TodoListFilter.allTitle).tag("")
                            ForEach(lists) { list in
                                Text(list.name).tag(list.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Liste")
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
        onSave(text, person, prioA, prioB, dueDate, TodoJSON.normalizedListId(listId))
        dismiss()
    }
}

private struct TodoListsSheet: View {
    let lists: [TodoNamedList]
    var onRename: (String, String) -> Void
    var onDelete: (TodoNamedList) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.einkaufTheme) private var theme
    @State private var renaming: TodoNamedList?
    @State private var renameDraft = ""
    @State private var pendingDelete: TodoNamedList?

    var body: some View {
        NavigationStack {
            List {
                if lists.isEmpty {
                    Text("Noch keine Listen.")
                        .foregroundStyle(theme.muted)
                        .einkaufRowChrome()
                } else {
                    ForEach(lists) { list in
                        HStack {
                            Text(list.name)
                                .foregroundStyle(theme.ink)
                            Spacer()
                            Button("Umbenennen") {
                                renaming = list
                                renameDraft = list.name
                            }
                            .buttonStyle(.borderless)
                            Button("Löschen", role: .destructive) {
                                pendingDelete = list
                            }
                            .buttonStyle(.borderless)
                        }
                        .einkaufRowChrome()
                    }
                    .onDelete { offsets in
                        for index in offsets where lists.indices.contains(index) {
                            pendingDelete = lists[index]
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .einkaufListChrome()
            .navigationTitle("Listen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Liste umbenennen", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $renameDraft)
                Button("Fertig") {
                    if let list = renaming {
                        onRename(list.id, renameDraft)
                    }
                    renaming = nil
                }
                Button("Abbrechen", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(
                "Liste löschen",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let list = pendingDelete {
                        onDelete(list)
                    }
                    pendingDelete = nil
                }
                Button("Abbrechen", role: .cancel) { pendingDelete = nil }
            } message: {
                if let list = pendingDelete {
                    Text("Liste „\(list.name)“ wirklich löschen? Aufgaben bleiben ohne Liste.")
                }
            }
        }
    }
}

private enum TodoImportUTTypes {
    static var all: [UTType] {
        var types: [UTType] = [.json, .commaSeparatedText]
        types.append(TodoFileDocument.markdownType)
        if let markdown = UTType(filenameExtension: "markdown") {
            types.append(markdown)
        }
        return types
    }
}

private struct TodoFileDocument: FileDocument {
    static var markdownType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    static var readableContentTypes: [UTType] { [.json, .plainText, .commaSeparatedText, markdownType] }
    static var writableContentTypes: [UTType] { [.json, .plainText, .commaSeparatedText, markdownType] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    TodoListView()
        .environmentObject(TodoStore(state: .empty, enableSync: false))
        .environmentObject(AppearanceSettings())
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
