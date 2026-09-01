import Foundation
import Combine

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var state: AppState
    @Published var lastError: String?

    private var sync: ConnectivitySync?
    private var saveTask: Task<Void, Never>?

    init(state: AppState? = nil, enableSync: Bool = true) {
        if let state {
            self.state = BackupCodec.normalized(state)
        } else {
            self.state = Persistence.load() ?? .seed
        }
        if enableSync {
            let bridge = ConnectivitySync()
            bridge.store = self
            self.sync = bridge
            bridge.start()
        }
    }

    var groups: [DeptGroup] { state.grouped() }
    var stores: [Store] { state.stores }
    var staples: [Staple] { state.staples }
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
        let item = state.items[idx]
        sync?.broadcastToggle(id: item.id, done: item.done, at: item.doneChangedAt ?? Date.nowEpochMillis, state: state)
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
        let name = rawName.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let item = Item(
            id: Item.makeID(),
            name: name,
            dept: DepartmentGuesser.guess(name, mappings: state.mappings),
            done: false,
            added: Date.nowEpochMillis,
            ord: nextOrd(),
            doneChangedAt: Date.nowEpochMillis
        )
        state.items.append(item)
        state.listRevision += 1
        persistAndSync()
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
        let group = groups.first(where: { $0.id == dept })?.items ?? []
        let ids = Set(offsets.compactMap { group.indices.contains($0) ? group[$0].id : nil })
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

    func moveLayoutDept(_ id: String, by: Int) {
        mutateCurrentStoreLayout { StoreLayout.move($0, id: id, by: by) }
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
        state.currentStoreId = id
        state.listRevision += 1
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
        if merged.listRevision > incoming.listRevision || hasNewerDones(local: merged, remote: incoming) {
            sync?.broadcast(merged)
        }
    }

    func snapshotForPeer() -> AppState { state }

    private func hasNewerDones(local: AppState, remote: AppState) -> Bool {
        let remoteById = Dictionary(uniqueKeysWithValues: remote.items.map { ($0.id, $0) })
        for item in local.items {
            let localAt = item.doneChangedAt ?? 0
            let remoteAt = remoteById[item.id]?.doneChangedAt ?? 0
            if localAt > remoteAt { return true }
        }
        return false
    }

    private func nextOrd() -> Double {
        (state.items.map(\.sortOrd).max() ?? 0) + 1
    }

    private func persistAndSync() {
        persistQuietly()
        sync?.broadcast(state)
    }

    private func persistQuietly() {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            Persistence.save(snapshot)
        }
        Persistence.save(state)
    }
}
