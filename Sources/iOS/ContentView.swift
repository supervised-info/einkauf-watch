import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ShoppingStore
    @EnvironmentObject private var appearance: AppearanceSettings
    @Environment(\.einkaufTheme) private var theme
    @State private var draft = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = BackupFileDocument(data: Data())
    @State private var shareItem: BackupShareItem?
    @State private var alertMessage: String?
    @State private var showSettings = false
    @State private var renamingID: String?
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if store.groups.isEmpty {
                    ContentUnavailableView("Noch nichts auf der Liste.", systemImage: "basket", description: Text("Artikel hinzufügen oder ein Backup importieren."))
                        .foregroundStyle(theme.ink)
                } else {
                    list
                }
            }
            .background(theme.paper)
            .navigationTitle("Einkaufsliste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "einkauf-backup") { result in
                if case .failure(let error) = result {
                    alertMessage = error.localizedDescription
                }
            }
            .alert("Hinweis", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .onChange(of: store.lastError) { _, new in
                if let new { alertMessage = new }
            }
            .onOpenURL { url in
                do {
                    try store.importBackup(from: url)
                } catch {
                    alertMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
                    .environmentObject(store)
                    .environmentObject(appearance)
                    .environment(\.einkaufTheme, theme)
                    .preferredColorScheme(appearance.preferredColorScheme)
                    .einkaufScreen(theme)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var list: some View {
        Group {
            if store.walkMode {
                walkList
            } else {
                editList
            }
        }
    }

    private var walkList: some View {
        List {
            ForEach(store.groups) { group in
                Section {
                    ForEach(group.items) { item in
                        walkRow(item)
                    }
                } header: {
                    Text(group.title)
                        .foregroundStyle(theme.muted)
                        .textCase(.uppercase)
                }
            }
        }
        .listStyle(.insetGrouped)
        .einkaufListChrome()
        .environment(\.editMode, .constant(.inactive))
        .id("\(store.state.currentStoreId)|\(store.state.currentStore.layout.joined())")
    }

    /// Flache Liste: Überschriften sind nicht verschiebbar, Artikel können in jede sichtbare
    /// Abteilung (inkl. vor/nach). Per-Section-`onMove` kann das in SwiftUI nicht.
    private var editList: some View {
        List {
            ForEach(store.editRows) { row in
                switch row {
                case .header(let dept):
                    Text(Department.title(for: dept))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                        .deleteDisabled(true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel(Department.title(for: dept))
                case .item(let item):
                    editRow(item)
                }
            }
            .onMove { store.moveEditRows(from: $0, to: $1) }
            .onDelete { store.deleteEditRows(at: $0) }
        }
        .listStyle(.insetGrouped)
        .einkaufListChrome()
        .environment(\.editMode, .constant(.active))
        .id("\(store.state.currentStoreId)|\(store.state.currentStore.layout.joined())")
    }

    private func walkRow(_ item: Item) -> some View {
        Button {
            store.toggle(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.done ? theme.good : theme.muted)
                Text(item.name)
                    .foregroundStyle(theme.ink)
                    .strikethrough(item.done, color: theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .einkaufRowChrome()
        .accessibilityLabel(item.name)
        .accessibilityValue(item.done ? "erledigt" : "offen")
    }

    private func editRow(_ item: Item) -> some View {
        HStack(spacing: 10) {
            Button {
                store.toggle(item.id)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.done ? theme.good : theme.muted)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.done ? "Erledigt: \(item.name)" : "Offen: \(item.name)")

            if renamingID == item.id {
                TextField("Name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .submitLabel(.done)
                    .onSubmit(commitRename)
                    .onChange(of: renameFocused) { _, focused in
                        if !focused { commitRename() }
                    }
                    .strikethrough(item.done, color: theme.muted)
            } else {
                Button {
                    beginRename(item)
                } label: {
                    Text(item.name)
                        .foregroundStyle(theme.ink)
                        .strikethrough(item.done, color: theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Umbenennen: \(item.name)")
            }

            Picker("Abteilung", selection: Binding(
                get: { Department.resolved(item.dept) },
                set: { store.setItemDept(item.id, dept: $0) }
            )) {
                ForEach(Department.allCases) { dept in
                    Text(dept.title).tag(dept.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Abteilung für \(item.name)")
        }
        .padding(.vertical, 2)
        .einkaufRowChrome()
    }

    private func beginRename(_ item: Item) {
        renamingID = item.id
        renameDraft = item.name
        renameFocused = true
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        store.renameItem(id, to: renameDraft)
        renamingID = nil
        renameFocused = false
        renameDraft = ""
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(store.stores) { s in
                    Button {
                        store.setStore(s.id)
                    } label: {
                        if s.id == store.state.currentStoreId {
                            Label(s.name, systemImage: "checkmark")
                        } else {
                            Text(s.name)
                        }
                    }
                }
            } label: {
                Text(store.state.currentStore.name)
            }
            .accessibilityLabel("Laden")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(store.walkMode ? "Bearbeiten" : "Geh-Modus") {
                if store.walkMode == false {
                    commitRename()
                }
                store.toggleWalkMode()
            }
            .accessibilityLabel(store.walkMode ? "Bearbeiten" : "Geh-Modus")
            .accessibilityAddTraits(store.walkMode ? .isSelected : [])
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Backup importieren…", systemImage: "square.and.arrow.down") {
                    showImporter = true
                }
                Button("Backup exportieren…", systemImage: "square.and.arrow.up") {
                    do {
                        exportDocument = BackupFileDocument(data: try store.exportBackup())
                        showExporter = true
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                }
                Button("Backup teilen", systemImage: "square.and.arrow.up.on.square") {
                    shareBackup()
                }
                Menu("Stamm") {
                    Button("Gesamtliste") {
                        store.applyAllStaples()
                    }
                    if !store.staples.isEmpty {
                        Divider()
                        ForEach(Array(store.staples.enumerated()), id: \.offset) { _, staple in
                            Button(staple.name) { store.applyStaple(staple) }
                        }
                    }
                }
                Button("Erledigte löschen", systemImage: "trash") {
                    store.clearDone()
                }
                Divider()
                Button("Einstellungen", systemImage: "gearshape") {
                    showSettings = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Mehr")
        }
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("Milch, Äpfel, Klopapier…", text: $draft)
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
        store.addItem(draft)
        draft = ""
    }

    private func shareBackup() {
        do {
            let data = try store.exportBackup()
            let url = try BackupShare.writeTempFile(data: data)
            guard FileManager.default.fileExists(atPath: url.path) else {
                alertMessage = "Backup-Datei konnte nicht erzeugt werden."
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
                try store.importBackup(from: url)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

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
    ContentView()
        .environmentObject(ShoppingStore(state: .seed, enableSync: false))
        .environmentObject(AppearanceSettings())
        .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
