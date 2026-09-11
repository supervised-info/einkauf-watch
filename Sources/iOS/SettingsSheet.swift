import SwiftUI
import UniformTypeIdentifiers

struct SettingsSheet: View {
    @EnvironmentObject private var store: ShoppingStore
    @EnvironmentObject private var todos: TodoStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.einkaufTheme) private var theme
    @State private var newStapleName = ""
    @State private var newStoreName = ""
    @State private var confirmDeleteStore = false
    @State private var pendingDeleteStoreId: String?
    @State private var confirmDeleteSavedList = false
    @State private var pendingDeleteSavedListId: String?
    @State private var showEinkaufImporter = false
    @State private var showEinkaufExporter = false
    @State private var einkaufExportDocument = BackupFileDocument(data: Data())
    @State private var showTodoImporter = false
    @State private var showTodoExporter = false
    @State private var todoExportDocument = BackupFileDocument(data: Data())
    @State private var todoShareItem: BackupShareItem?
    @State private var todoAlertMessage: String?
    @State private var pendingTodoImport: Data?
    @State private var showTodoImportChoice = false
    @State private var todoImportSummary = ""
    @State private var showInboxImporter = false
    @State private var inboxDisplayName = InboxBookmarkStore.displayName
    @State private var inboxRetrieve: InboxRetrieveSession?

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
                    Text("Allgemein")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Creme ist das Vintage-Papier, Blau die Navy-Palette. System folgt der iPhone-Einstellung für Hell und Dunkel.")
                }

                Section {
                    Button("Backup importieren…") {
                        showEinkaufImporter = true
                    }
                    .einkaufRowChrome()
                    Button("Backup exportieren…") {
                        exportEinkaufJSON()
                    }
                    .einkaufRowChrome()
                    Button("Backup teilen") {
                        shareEinkaufBackup()
                    }
                    .einkaufRowChrome()
                    NavigationLink {
                        ArchiveListView(kind: .einkauf)
                    } label: {
                        Text("Archiv…")
                    }
                    .einkaufRowChrome()
                    Button("Archiv teilen") {
                        shareEinkaufArchive()
                    }
                    .einkaufRowChrome()
                    Button("Inbox verbinden…") {
                        showInboxImporter = true
                    }
                    .einkaufRowChrome()
                    Button("Inbox abrufen") {
                        retrieveInbox()
                    }
                    .einkaufRowChrome()
                    if let name = inboxDisplayName {
                        Text(name)
                            .foregroundStyle(theme.muted)
                            .einkaufRowChrome()
                    }
                } header: {
                    Text("Einkauf")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Backup-JSON (einkauf-backup). Archiv gelöschter erledigter Artikel (einkauf-archiv.json), einzeln löschen. Inbox verbinden und abrufen. History wird nur angehängt, nie überschrieben.")
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
                        .deleteDisabled(s.builtin)
                    }
                    .onDelete(perform: requestDeleteStores)
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
                    ForEach(Array(store.staples.enumerated()), id: \.element.name) { idx, staple in
                        stapleRow(idx: idx, staple: staple)
                    }
                    .onMove { store.moveStaples(from: $0, to: $1) }
                    .environment(\.editMode, .constant(.active))
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
                    Text("Stamm-Artikel erscheinen im Menü Stamm in dieser Reihenfolge und können mit Gesamtliste auf einmal auf die Liste. Ziehen oder Pfeile ändern die Reihenfolge.")
                }

                Section {
                    if store.savedLists.isEmpty {
                        Text("Noch keine gespeicherten Listen.")
                            .foregroundStyle(theme.muted)
                            .einkaufRowChrome()
                            .deleteDisabled(true)
                    } else {
                        ForEach(store.savedLists) { list in
                            Button {
                                store.applySavedList(list)
                            } label: {
                                Text(list.name)
                                    .foregroundStyle(theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityLabel(list.name)
                            .einkaufRowChrome()
                        }
                        .onDelete(perform: requestDeleteSavedLists)
                    }
                } header: {
                    Text("Gespeicherte Listen")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("Anlass-Listen wie Grillen oder Drogerie. Tippen füllt die aktuelle Liste auf, ohne sie zu ersetzen. Wischen zum Löschen.")
                }

                Section {
                    NavigationLink {
                        KeywordDictionaryView()
                    } label: {
                        Text("Wörterbuch")
                    }
                    .einkaufRowChrome()
                }

                Section {
                    Button("Backup importieren…") {
                        showTodoImporter = true
                    }
                    .einkaufRowChrome()
                    Button("Backup exportieren…") {
                        exportTodoJSON()
                    }
                    .einkaufRowChrome()
                    Button("Backup teilen") {
                        shareTodoJSON()
                    }
                    .einkaufRowChrome()
                    NavigationLink {
                        ArchiveListView(kind: .todo)
                    } label: {
                        Text("Archiv…")
                    }
                    .einkaufRowChrome()
                    Button("Archiv teilen") {
                        shareTodoArchive()
                    }
                    .einkaufRowChrome()
                } header: {
                    Text("To-Do")
                        .foregroundStyle(theme.muted)
                } footer: {
                    Text("JSON-Backup der To-Do-Liste (todo-liste.json). Einkauf-Backups werden abgelehnt. Archiv gelöschter erledigter Aufgaben: todo-archiv.json, einzeln löschen.")
                }
            }
            .einkaufListChrome()
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Laden „\(pendingDeleteStoreName)“ wirklich löschen?",
                isPresented: $confirmDeleteStore,
                titleVisibility: .visible
            ) {
                Button("Laden löschen", role: .destructive) {
                    if let id = pendingDeleteStoreId {
                        store.deleteStore(id: id)
                    }
                    pendingDeleteStoreId = nil
                }
                Button("Abbrechen", role: .cancel) {
                    pendingDeleteStoreId = nil
                }
            }
            .confirmationDialog(
                "Gespeicherte Liste „\(pendingDeleteSavedListName)“ wirklich löschen?",
                isPresented: $confirmDeleteSavedList,
                titleVisibility: .visible
            ) {
                Button("Liste löschen", role: .destructive) {
                    if let id = pendingDeleteSavedListId {
                        store.removeSavedList(id: id)
                    }
                    pendingDeleteSavedListId = nil
                }
                Button("Abbrechen", role: .cancel) {
                    pendingDeleteSavedListId = nil
                }
            }
            .fileImporter(
                isPresented: $showEinkaufImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleEinkaufImport(result)
            }
            .background {
                Color.clear
                    .fileImporter(
                        isPresented: $showTodoImporter,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: false
                    ) { result in
                        handleTodoImport(result)
                    }
            }
            .background {
                Color.clear
                    .fileImporter(
                        isPresented: $showInboxImporter,
                        allowedContentTypes: Self.inboxContentTypes,
                        allowsMultipleSelection: false
                    ) { result in
                        handleInboxConnect(result)
                    }
            }
            .fileExporter(
                isPresented: $showEinkaufExporter,
                document: einkaufExportDocument,
                contentType: .json,
                defaultFilename: "einkauf-backup"
            ) { result in
                if case .failure(let error) = result {
                    todoAlertMessage = error.localizedDescription
                }
            }
            .background {
                Color.clear
                    .fileExporter(
                        isPresented: $showTodoExporter,
                        document: todoExportDocument,
                        contentType: .json,
                        defaultFilename: "todo-liste"
                    ) { result in
                        if case .failure(let error) = result {
                            todoAlertMessage = error.localizedDescription
                        }
                    }
            }
            .sheet(item: $todoShareItem) { item in
                ShareSheet(url: item.url)
                    .ignoresSafeArea()
            }
            .sheet(item: $inboxRetrieve) { session in
                InboxRetrieveSheet(
                    items: session.items,
                    onConfirm: { selected in
                        confirmInboxRetrieve(session: session, selectedOffsets: selected)
                    },
                    onDeleteRemaining: { remaining in
                        rewriteInboxRetrieve(session: session, remainingItems: remaining)
                    }
                )
                .environment(\.einkaufTheme, theme)
                .preferredColorScheme(appearance.preferredColorScheme)
                .einkaufScreen(theme)
            }
            .alert("Hinweis", isPresented: Binding(
                get: { todoAlertMessage != nil },
                set: { if !$0 { todoAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { todoAlertMessage = nil }
            } message: {
                Text(todoAlertMessage ?? "")
            }
            .confirmationDialog("To-Do importieren", isPresented: $showTodoImportChoice, titleVisibility: .visible) {
                Button("Anhängen") { commitPendingTodo(append: true) }
                Button("Ersetzen") { commitPendingTodo(append: false) }
                Button("Abbrechen", role: .cancel) { pendingTodoImport = nil }
            } message: {
                Text(todoImportSummary)
            }
            .onChange(of: todos.lastError) { _, new in
                if let new { todoAlertMessage = new }
            }
            .onChange(of: store.lastError) { _, new in
                if let new { todoAlertMessage = new }
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
                Button {
                    store.moveStaple(at: idx, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Nach oben")
                .disabled(!canMoveStaple(at: idx, by: -1))

                Button {
                    store.moveStaple(at: idx, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Nach unten")
                .disabled(!canMoveStaple(at: idx, by: 1))

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

    private func canMoveStaple(at idx: Int, by: Int) -> Bool {
        store.staples.indices.contains(idx + by)
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

    private var pendingDeleteStoreName: String {
        guard let id = pendingDeleteStoreId else { return "" }
        return store.stores.first(where: { $0.id == id })?.name ?? ""
    }

    private func requestDeleteStores(at offsets: IndexSet) {
        let custom = offsets.compactMap { index -> Store? in
            guard store.stores.indices.contains(index) else { return nil }
            let s = store.stores[index]
            return s.builtin ? nil : s
        }
        guard let victim = custom.first else { return }
        pendingDeleteStoreId = victim.id
        confirmDeleteStore = true
    }

    private var pendingDeleteSavedListName: String {
        guard let id = pendingDeleteSavedListId else { return "" }
        return store.savedLists.first(where: { $0.id == id })?.name ?? ""
    }

    private func requestDeleteSavedLists(at offsets: IndexSet) {
        guard let idx = offsets.first, store.savedLists.indices.contains(idx) else { return }
        pendingDeleteSavedListId = store.savedLists[idx].id
        confirmDeleteSavedList = true
    }

    private func exportEinkaufJSON() {
        do {
            einkaufExportDocument = BackupFileDocument(data: try store.exportBackup())
            showEinkaufExporter = true
        } catch {
            todoAlertMessage = error.localizedDescription
        }
    }

    private func exportTodoJSON() {
        do {
            todoExportDocument = BackupFileDocument(data: try todos.exportBackup())
            showTodoExporter = true
        } catch {
            todoAlertMessage = error.localizedDescription
        }
    }

    private func shareEinkaufBackup() {
        shareFile(
            data: { try store.exportBackup() },
            stem: BackupShare.einkaufStem,
            missing: "Backup-Datei konnte nicht erzeugt werden."
        )
    }

    private func shareTodoJSON() {
        shareFile(
            data: { try todos.exportBackup() },
            stem: BackupShare.todoStem,
            missing: "Backup-Datei konnte nicht erzeugt werden."
        )
    }

    private func shareEinkaufArchive() {
        shareFile(
            data: { try store.exportArchive() },
            stem: BackupShare.einkaufArchiveStem,
            missing: "Archiv-Datei konnte nicht erzeugt werden."
        )
    }

    private func shareTodoArchive() {
        shareFile(
            data: { try todos.exportArchive() },
            stem: BackupShare.todoArchiveStem,
            missing: "Archiv-Datei konnte nicht erzeugt werden."
        )
    }

    private func shareFile(data: () throws -> Data, stem: String, missing: String) {
        do {
            let payload = try data()
            let url = try BackupShare.writeTempFile(data: payload, stem: stem, ext: "json")
            guard FileManager.default.fileExists(atPath: url.path) else {
                todoAlertMessage = missing
                return
            }
            todoShareItem = BackupShareItem(url: url)
        } catch {
            todoAlertMessage = error.localizedDescription
        }
    }

    private func handleEinkaufImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            todoAlertMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try store.importBackup(from: url)
            } catch {
                todoAlertMessage = error.localizedDescription
            }
        }
    }

    private func handleTodoImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            todoAlertMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try IncomingJSON.data(from: url)
                try offerOrApplyTodo(data)
            } catch {
                todoAlertMessage = error.localizedDescription
            }
        }
    }

    private func offerOrApplyTodo(_ data: Data) throws {
        if let summary = try TodoImport.offer(data, into: todos) {
            pendingTodoImport = data
            todoImportSummary = summary
            showTodoImportChoice = true
        }
    }

    private func commitPendingTodo(append: Bool) {
        guard let data = pendingTodoImport else { return }
        pendingTodoImport = nil
        do {
            try todos.importAny(data, append: append)
        } catch {
            todoAlertMessage = error.localizedDescription
        }
    }

    private static let inboxContentTypes: [UTType] = {
        var types: [UTType] = [.plainText, .text]
        if let txt = UTType(filenameExtension: "txt") {
            types.append(txt)
        }
        return types
    }()

    private func handleInboxConnect(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            todoAlertMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try InboxBookmarkStore.connect(url: url)
                inboxDisplayName = InboxBookmarkStore.displayName
                todoAlertMessage = "Inbox verbunden."
            } catch {
                InboxBookmarkStore.clear()
                inboxDisplayName = nil
                todoAlertMessage = error.localizedDescription
            }
        }
    }

    private func retrieveInbox() {
        guard InboxBookmarkStore.hasBookmark else {
            todoAlertMessage = "Zuerst Inbox verbinden…"
            return
        }
        Task {
            do {
                let session = try await InboxBookmarkStore.beginRetrieve()
                guard !session.items.isEmpty else {
                    session.stopAccess()
                    todoAlertMessage = InboxParser.retrieveConfirmation(addedCount: 0)
                    return
                }
                inboxRetrieve = session
            } catch {
                if let inboxError = error as? InboxBookmarkError, inboxError == .stale {
                    InboxBookmarkStore.clear()
                    inboxDisplayName = nil
                }
                todoAlertMessage = error.localizedDescription
            }
        }
    }

    private func confirmInboxRetrieve(session: InboxRetrieveSession, selectedOffsets: Set<Int>) {
        let partition = InboxParser.partition(items: session.items, selectedOffsets: selectedOffsets)
        guard !partition.selected.isEmpty else {
            todoAlertMessage = InboxParser.noneSelectedMessage()
            return
        }
        do {
            let added = store.addItems(fromSpeech: InboxParser.speechText(from: partition.selected), imported: true)
            try session.rewriteRemaining(partition.remainder)
            session.stopAccess()
            inboxRetrieve = nil
            todoAlertMessage = InboxParser.retrieveConfirmation(addedCount: added)
        } catch {
            session.stopAccess()
            inboxRetrieve = nil
            todoAlertMessage = error.localizedDescription
        }
    }

    /// Löschen im Sheet: Datei sofort auf die restlichen Zeilen kürzen, ohne Import.
    private func rewriteInboxRetrieve(session: InboxRetrieveSession, remainingItems: [String]) -> String? {
        do {
            try session.rewriteRemaining(remainingItems)
            if remainingItems.isEmpty {
                session.stopAccess()
                inboxRetrieve = nil
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

#Preview {
    SettingsSheet()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environmentObject(TodoStore(state: .empty, enableSync: false))
        .environmentObject(AppearanceSettings())
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
