import Foundation
import Combine

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var state: AppState {
        didSet { rebuildDerived() }
    }
    @Published private(set) var groups: [DeptGroup] = []
    @Published var lastError: String?

#if os(iOS) || os(watchOS)
    private var sync: ConnectivitySync?
#endif
    private var saveTask: Task<Void, Never>?

    init(state: AppState? = nil, enableSync: Bool = true) {
        if let state {
            self.state = BackupCodec.normalized(state)
        } else {
            self.state = Persistence.load() ?? .seed
        }
        rebuildDerived()
#if os(iOS) || os(watchOS)
        if enableSync {
            let bridge = ConnectivitySync()
            bridge.store = self
            self.sync = bridge
            bridge.start()
        }
#else
        _ = enableSync
#endif
    }

    var editRows: [ItemEditing.Row] { ItemEditing.rows(from: groups) }
    var walkLines: [WalkLine] { ListGrouping.walkLines(groups: groups, storeId: state.currentStoreId) }
    var walkListRows: [WalkListRow] { ListGrouping.walkListRows(groups: groups, storeId: state.currentStoreId) }
    func walkListRows(hidingCompleted: Bool) -> [WalkListRow] {
        ListGrouping.walkListRows(groups: groups, storeId: state.currentStoreId, hidingCompleted: hidingCompleted)
    }
    var stores: [Store] { state.stores }
    var staples: [Staple] { state.staples }
    var savedLists: [SavedList] { state.savedLists }
    var walkMode: Bool { state.walkMode }

    func setWalkMode(_ on: Bool) {
        guard state.walkMode != on else { return }
        state.walkMode = on
        persistAndSync()
    }

    func toggleWalkMode() {
        setWalkMode(!state.walkMode)
    }

    func toggle(_ id: String) {
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        state.items[idx].done.toggle()
        state.items[idx].doneChangedAt = Date.nowEpochMillis
        persistQuietly()
#if os(iOS) || os(watchOS)
        let item = state.items[idx]
        sync?.broadcastToggle(id: item.id, done: item.done, at: item.doneChangedAt ?? Date.nowEpochMillis, state: state)
#endif
    }

    func applyRemoteToggle(id: String, done: Bool, at: Double) {
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        let current = state.items[idx].doneChangedAt ?? 0
        guard at >= current else { return }
        state.items[idx].done = done
        state.items[idx].doneChangedAt = at
        persistQuietly()
        objectWillChange.send()
    }

    func addItem(_ rawName: String) {
        guard let item = makeItem(from: rawName, ord: nextOrd()) else { return }
        state.items.append(item)
        state.listRevision += 1
        persistAndSync()
    }

    /// iPhone / Tests: Splitter-Teile in **einem** State-Update + **einem** `persistAndSync`.
    /// Watch ruft das nicht auf (keine Spracheingabe).
    @discardableResult
    func addItems(fromSpeech text: String) -> Int {
        let count = appendSpeechItems(text)
        if count > 0 { persistAndSync() }
        return count
    }

    @discardableResult
    private func appendSpeechItems(_ text: String) -> Int {
        let names = SpeechItemSplitter.items(from: text)
        guard !names.isEmpty else { return 0 }
        var ord = nextOrd()
        var added: [Item] = []
        added.reserveCapacity(names.count)
        for name in names {
            guard let item = makeItem(from: name, ord: ord) else { continue }
            added.append(item)
            ord += 1
        }
        guard !added.isEmpty else { return 0 }
        state.items.append(contentsOf: added)
        state.listRevision += 1
        return added.count
    }

    private func makeItem(from rawName: String, ord: Double) -> Item? {
        let name = rawName.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return Item(
            id: Item.makeID(),
            name: name,
            dept: DepartmentGuesser.guess(name, mappings: state.mappings),
            done: false,
            added: Date.nowEpochMillis,
            ord: ord,
            doneChangedAt: Date.nowEpochMillis
        )
    }

    func renameItem(_ id: String, to rawName: String) {
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        guard let result = ItemEditing.rename(state.items[idx], to: rawName, mappings: state.mappings) else { return }
        guard result.0 != state.items[idx] || result.1 != state.mappings else { return }
        state.items[idx] = result.0
        state.mappings = result.1
        state.listRevision += 1
        persistAndSync()
    }

    func setItemDept(_ id: String, dept: String) {
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        guard let result = ItemEditing.setDept(state.items[idx], dept: dept, mappings: state.mappings) else { return }
        guard result.0 != state.items[idx] || result.1 != state.mappings else { return }
        state.items[idx] = result.0
        state.mappings = result.1
        state.listRevision += 1
        persistAndSync()
    }

    func deleteItems(in dept: String, at offsets: IndexSet) {
        let group = groups.first(where: { $0.dept == dept })?.items ?? []
        let ids = Set(offsets.compactMap { group.indices.contains($0) ? group[$0].id : nil })
        guard !ids.isEmpty else { return }
        state.items.removeAll { ids.contains($0.id) }
        state.listRevision += 1
        persistAndSync()
    }

    func deleteEditRows(at offsets: IndexSet) {
        let ids = Set(ItemEditing.itemIDs(in: editRows, at: offsets))
        guard !ids.isEmpty else { return }
        state.items.removeAll { ids.contains($0.id) }
        state.listRevision += 1
        persistAndSync()
    }

    func moveItems(in dept: String, from source: IndexSet, to destination: Int) {
        let next = ItemEditing.move(allItems: state.items, dept: dept, from: source, to: destination)
        guard next != state.items else { return }
        state.items = next
        state.listRevision += 1
        persistAndSync()
    }

    func moveEditRows(from source: IndexSet, to destination: Int) {
        guard let result = ItemEditing.moveRows(
            allItems: state.items,
            store: state.currentStore,
            from: source,
            to: destination,
            mappings: state.mappings
        ) else { return }
        guard result.items != state.items || result.mappings != state.mappings else { return }
        state.items = result.items
        state.mappings = result.mappings
        state.listRevision += 1
        persistAndSync()
    }

    func addStaple(_ staple: Staple) {
        applyStaple(staple)
    }

    /// Wie HTML `applyStaple`: fehlend anlegen, erledigt wieder öffnen, sonst überspringen.
    @discardableResult
    func applyStaple(_ staple: Staple) -> StapleApply.Outcome {
        let result = StapleApply.apply(
            staple,
            items: state.items,
            mappings: state.mappings,
            nextOrd: nextOrd()
        )
        guard result.didChange else { return result }
        state.items = result.items
        state.mappings = result.mappings
        state.listRevision += 1
        persistAndSync()
        return result
    }

    /// Wie HTML `applyAllStaples`: jeden Stamm-Artikel anlegen oder wieder öffnen.
    @discardableResult
    func applyAllStaples() -> StapleApply.Outcome {
        let result = StapleApply.applyAll(
            state.staples,
            items: state.items,
            mappings: state.mappings,
            nextOrd: nextOrd()
        )
        guard result.didChange else { return result }
        state.items = result.items
        state.mappings = result.mappings
        state.listRevision += 1
        persistAndSync()
        return result
    }

    enum SaveListOutcome: Equatable {
        case saved
        case emptyList
        case invalidName
    }

    /// Snapshot der aktuellen Artikel (Name + Abteilung, ohne Häkchen). Leere Liste wird nicht gespeichert.
    @discardableResult
    func saveCurrentList(name: String) -> SaveListOutcome {
        guard let trimmed = SavedList.sanitizedName(name) else { return .invalidName }
        let snapshot = SavedList.snapshot(from: state.items)
        guard !snapshot.isEmpty else { return .emptyList }
        state.savedLists.append(SavedList(id: SavedList.makeID(), name: trimmed, items: snapshot))
        state.listRevision += 1
        persistAndSync()
        return .saved
    }

    /// Wie Gesamtliste / `StapleApply`: fehlend anlegen, erledigt wieder öffnen, offen überspringen. Ersetzt die Liste nicht.
    @discardableResult
    func applySavedList(_ list: SavedList) -> StapleApply.Outcome {
        let result = StapleApply.applyAll(
            list.items,
            items: state.items,
            mappings: state.mappings,
            nextOrd: nextOrd()
        )
        guard result.didChange else { return result }
        state.items = result.items
        state.mappings = result.mappings
        state.listRevision += 1
        persistAndSync()
        return result
    }

    func removeSavedList(id: String) {
        let before = state.savedLists.count
        state.savedLists.removeAll { $0.id == id }
        guard state.savedLists.count != before else { return }
        state.listRevision += 1
        persistAndSync()
    }

    func createStaple(_ rawName: String) {
        let name = rawName.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let key = DepartmentGuesser.mappingKey(name)
        if state.staples.contains(where: { DepartmentGuesser.mappingKey($0.name) == key }) {
            return
        }
        let dept = DepartmentGuesser.guess(name, mappings: state.mappings)
        state.staples.append(Staple(name: name, dept: dept))
        state.listRevision += 1
        persistAndSync()
    }

    func removeStaple(at index: Int) {
        guard state.staples.indices.contains(index) else { return }
        state.staples.remove(at: index)
        state.listRevision += 1
        persistAndSync()
    }

    func setStapleDept(at index: Int, dept: String) {
        guard state.staples.indices.contains(index), Department.isKnown(dept) else { return }
        state.staples[index].dept = dept
        state.mappings[DepartmentGuesser.mappingKey(state.staples[index].name)] = dept
        state.listRevision += 1
        persistAndSync()
    }

    /// Schreibt `mappings[mappingKey(key)]` — dasselbe Backup-Feld wie die PWA, kein zweites Dictionary.
    func setMapping(_ key: String, dept: String) {
        let mapped = DepartmentGuesser.mappingKey(key)
        guard !mapped.isEmpty, Department.isKnown(dept) else { return }
        guard state.mappings[mapped] != dept else { return }
        state.mappings[mapped] = dept
        state.listRevision += 1
        persistAndSync()
    }

    func removeMapping(_ key: String) {
        guard state.mappings[key] != nil else { return }
        state.mappings.removeValue(forKey: key)
        state.listRevision += 1
        persistAndSync()
    }

    func moveLayoutDept(_ id: String, by: Int) {
        mutateCurrentStoreLayout { StoreLayout.move($0, id: id, by: by) }
    }

    func moveLayoutDepts(from source: IndexSet, to destination: Int) {
        mutateCurrentStoreLayout { StoreLayout.moving($0, from: source, to: destination) }
    }

    func addLayoutDept(_ id: String) {
        mutateCurrentStoreLayout { StoreLayout.adding(id, to: $0) }
    }

    func removeLayoutDept(_ id: String) {
        mutateCurrentStoreLayout { StoreLayout.removing(id, from: $0) }
    }

    func resetLayout() {
        mutateCurrentStoreLayout { StoreLayout.reset(storeId: state.currentStoreId, current: $0) }
    }

    func createStore(_ rawName: String) {
        guard let created = StoreCatalog.create(name: rawName, copying: state.currentStore) else { return }
        state.stores.append(created)
        state.stores = BackupCodec.mergeBuiltinSeeds(state.stores)
        state.currentStoreId = created.id
        state.listRevision += 1
        persistAndSync()
    }

    func deleteStore(id: String) {
        guard let result = StoreCatalog.delete(id: id, stores: state.stores, currentId: state.currentStoreId) else { return }
        guard result.stores != state.stores || result.currentId != state.currentStoreId else { return }
        state.stores = result.stores
        state.currentStoreId = result.currentId
        state.listRevision += 1
        persistAndSync()
    }

    private func mutateCurrentStoreLayout(_ transform: ([String]) -> [String]) {
        guard let idx = state.stores.firstIndex(where: { $0.id == state.currentStoreId }) else { return }
        let next = transform(state.stores[idx].layout)
        guard next != state.stores[idx].layout else { return }
        state.stores[idx].layout = next
        state.listRevision += 1
        persistAndSync()
    }

    func setStore(_ id: String) {
        guard state.stores.contains(where: { $0.id == id }) else { return }
        var next = state
        next.currentStoreId = id
        next.listRevision += 1
        state = next
        persistAndSync()
    }

    func clearDone() {
        let before = state.items.count
        state.items.removeAll { $0.done }
        guard state.items.count != before else { return }
        state.listRevision += 1
        persistAndSync()
    }

    func importBackup(_ data: Data) throws {
        var imported = try BackupCodec.decode(data)
        imported.listRevision = max(state.listRevision, imported.listRevision) + 1
        state = imported
        lastError = nil
        persistAndSync()
    }

    func importBackup(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        try importBackup(data)
    }

    func exportBackup() throws -> Data {
        try BackupCodec.encodeExport(state)
    }

    func applyRemoteSnapshot(_ incoming: AppState) {
        let merged = StateMerge.merge(local: state, remote: incoming)
        guard merged != state else { return }
        state = merged
        persistQuietly()
#if os(iOS) || os(watchOS)
        if merged.listRevision > incoming.listRevision || hasNewerDones(local: merged, remote: incoming) {
            sync?.broadcast(merged)
        }
#endif
    }

    func snapshotForPeer() -> AppState { state }

#if os(iOS) || os(watchOS)
    private func hasNewerDones(local: AppState, remote: AppState) -> Bool {
        let remoteById = Dictionary(uniqueKeysWithValues: remote.items.map { ($0.id, $0) })
        for item in local.items {
            let localAt = item.doneChangedAt ?? 0
            let remoteAt = remoteById[item.id]?.doneChangedAt ?? 0
            if localAt > remoteAt { return true }
        }
        return false
    }
#endif

    private func nextOrd() -> Double {
        (state.items.map(\.sortOrd).max() ?? 0) + 1
    }

    private func persistAndSync() {
        persistQuietly()
#if os(iOS) || os(watchOS)
        sync?.broadcast(state)
#endif
    }

    private func rebuildDerived() {
        groups = state.grouped()
    }

    private func persistQuietly() {
        rebuildDerived()
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            Persistence.save(snapshot)
            reloadComplicationsAndWidgets()
        }
        Persistence.save(state)
        reloadComplicationsAndWidgets()
    }

    private func reloadComplicationsAndWidgets() {
#if os(watchOS)
        WatchComplicationReload.timelines()
#endif
#if os(iOS)
        HomeWidgetReload.timelines()
#endif
    }
}
