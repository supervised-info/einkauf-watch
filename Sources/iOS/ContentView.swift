import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ShoppingStore
    @State private var draft = ""
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportDocument = BackupFileDocument(data: Data())
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
                } else {
                    list
                }
            }
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
            }
        }
        .tint(Color(red: 0.61, green: 0.20, blue: 0.14))
    }

    private var list: some View {
        List {
            ForEach(store.groups) { group in
                Section(group.title) {
                    if store.walkMode {
                        ForEach(group.items) { item in
                            walkRow(item)
                        }
                    } else {
                        ForEach(group.items) { item in
                            editRow(item)
                        }
                        .onMove { store.moveItems(in: group.id, from: $0, to: $1) }
                        .onDelete { store.deleteItems(in: group.id, at: $0) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(store.walkMode ? .inactive : .active))
    }

    private func walkRow(_ item: Item) -> some View {
        Button {
            store.toggle(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.done ? Color(red: 0.17, green: 0.42, blue: 0.29) : Color.secondary)
                Text(item.name)
                    .foregroundStyle(.primary)
                    .strikethrough(item.done, color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(item.done ? Color(red: 0.17, green: 0.42, blue: 0.29) : Color.secondary)
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
                    .strikethrough(item.done, color: .secondary)
            } else {
                Button {
                    beginRename(item)
                } label: {
                    Text(item.name)
                        .foregroundStyle(.primary)
                        .strikethrough(item.done, color: .secondary)
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
            Picker("Laden", selection: Binding(
                get: { store.state.currentStoreId },
                set: { store.setStore($0) }
            )) {
                ForEach(store.stores) { s in
                    Text(s.name).tag(s.id)
                }
            }
            .pickerStyle(.menu)
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
        .background(.bar)
    }

    private func submit() {
        store.addItem(draft)
        draft = ""
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
}
