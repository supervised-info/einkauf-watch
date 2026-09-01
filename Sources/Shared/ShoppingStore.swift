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

    func addStaple(_ staple: Staple) {
        let key = DepartmentGuesser.mappingKey(staple.name)
        if state.items.contains(where: { DepartmentGuesser.mappingKey($0.name) == key && !$0.done }) {
            return
        }
        let item = Item(
            id: Item.makeID(),
            name: staple.name,
            dept: Department.isKnown(staple.dept) ? staple.dept : DepartmentGuesser.guess(staple.name, mappings: state.mappings),
            done: false,
            added: Date.nowEpochMillis,
            ord: nextOrd(),
            doneChangedAt: Date.nowEpochMillis
        )
        state.items.append(item)
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

    func loadSampleFromBundle() {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "einkauf-backup", withExtension: "json")
            ?? bundle.url(forResource: "einkauf-backup", withExtension: "json", subdirectory: "Fixtures")
        guard let url, let data = try? Data(contentsOf: url) else {
            lastError = "Beispiel-Liste nicht im App-Bundle gefunden."
            return
        }
        do {
            try importBackup(data)
        } catch {
            lastError = error.localizedDescription
        }
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
