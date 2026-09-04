import Foundation
import Combine

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var state: TodoState
    @Published var lastError: String?

#if os(iOS) || os(watchOS)
    private var sync: TodoConnectivitySync?
#endif
    private var saveTask: Task<Void, Never>?
    private var diskObserver: NSObjectProtocol?

    init(state: TodoState? = nil, enableSync: Bool = true) {
        if let state {
            self.state = TodoCodec.normalized(state)
        } else {
            self.state = TodoPersistence.load() ?? .empty
        }
#if os(iOS) || os(watchOS)
        if enableSync {
            let bridge = TodoConnectivitySync()
            bridge.store = self
            self.sync = bridge
            bridge.start()
        }
#else
        _ = enableSync
#endif
        diskObserver = NotificationCenter.default.addObserver(
            forName: .todoStateDidChangeOnDisk,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromPersistenceIfNewer()
            }
        }
    }

    deinit {
        if let diskObserver {
            NotificationCenter.default.removeObserver(diskObserver)
        }
    }

    func reloadFromPersistenceIfNewer() {
        guard let loaded = TodoPersistence.load() else { return }
        guard loaded.revision > state.revision else { return }
        state = TodoCodec.normalized(loaded)
#if os(iOS) || os(watchOS)
        sync?.broadcast(state)
#endif
    }

    /// Watch-Siri: Pending-Queue drainen, dann persist+sync auf dem live Store.
    func consumeSiriPendingAdds() {
        let pending = TodoSiriPendingAdds.drain()
        for speech in pending {
            addItems(fromSpeech: speech)
        }
    }

    /// Siri / gesprochene Listen: Splitter, dann derselbe Pfad wie getipptes Hinzufügen, ein Persist.
    @discardableResult
    func addItems(fromSpeech text: String) -> Int {
        let names = SpeechItemSplitter.items(from: SpeechItemSplitter.strippingTodoTriggerPrefix(text))
        guard !names.isEmpty else { return 0 }
        let now = TodoTime.nowIso()
        for name in names {
            let uid = takeUid()
            state.tasks.append(
                TodoTask(
                    uid: uid,
                    text: name,
                    completed: false,
                    createdAt: now,
                    updatedAt: now,
                    changedBy: TodoAuthor.app
                )
            )
        }
        state.revision += 1
        persistAndSync()
        return names.count
    }

    @discardableResult
    func add(
        _ rawText: String,
        person: String = "",
        prioA: String = "",
        prioB: String = "",
        dueDate: String = ""
    ) -> Int64? {
        let text = rawText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let now = TodoTime.nowIso()
        let uid = takeUid()
        state.tasks.append(
            TodoTask(
                uid: uid,
                text: text,
                completed: false,
                prioA: TodoJSON.prioA(prioA),
                prioB: TodoJSON.prioB(prioB),
                dueDate: TodoJSON.isoDate(dueDate),
                person: person.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: now,
                updatedAt: now,
                changedBy: TodoAuthor.app
            )
        )
        state.revision += 1
        persistAndSync()
        return uid
    }

    func toggle(_ uid: Int64) {
        guard let idx = state.tasks.firstIndex(where: { $0.uid == uid }) else { return }
        state.tasks[idx].completed.toggle()
        state.tasks[idx].completedDate = state.tasks[idx].completed ? TodoTime.todayIso() : ""
        state.tasks[idx].updatedAt = TodoTime.nowIso()
        persistQuietly()
#if os(iOS) || os(watchOS)
        let task = state.tasks[idx]
        sync?.broadcastToggle(uid: task.uid, completed: task.completed, at: task.updatedAt, state: state)
#endif
    }

    func applyRemoteToggle(uid: Int64, completed: Bool, at: String) {
        guard let idx = state.tasks.firstIndex(where: { $0.uid == uid }) else { return }
        let currentAt = TodoMerge.timestamp(state.tasks[idx].updatedAt)
        let incomingAt = TodoMerge.timestamp(at)
        if incomingAt < currentAt { return }
        if incomingAt == currentAt {
            if incomingAt == 0 {
                if !completed && state.tasks[idx].completed { return }
                if completed == state.tasks[idx].completed { return }
            } else if completed == state.tasks[idx].completed {
                return
            }
        }
        state.tasks[idx].completed = completed
        if completed {
            if state.tasks[idx].completedDate.isEmpty {
                state.tasks[idx].completedDate = TodoTime.todayIso()
            }
        } else {
            state.tasks[idx].completedDate = ""
        }
        if !at.isEmpty {
            state.tasks[idx].updatedAt = at
        }
        persistQuietly()
        objectWillChange.send()
    }

    func applyRemoteSnapshot(_ incoming: TodoState) {
        let merged = TodoMerge.merge(local: state, remote: incoming)
        guard merged != state else { return }
        state = merged
        persistQuietly()
#if os(iOS) || os(watchOS)
        if merged.revision > incoming.revision || hasNewerCompletions(local: merged, remote: incoming) {
            sync?.broadcast(merged)
        }
#endif
    }

    func snapshotForPeer() -> TodoState { state }

    func delete(_ uid: Int64) {
        let before = state.tasks.count
        state.tasks.removeAll { $0.uid == uid }
        guard state.tasks.count != before else { return }
        state.revision += 1
        persistAndSync()
    }

    func clearCompleted() {
        let before = state.tasks.count
        state.tasks.removeAll { $0.completed }
        guard state.tasks.count != before else { return }
        state.revision += 1
        persistAndSync()
    }

    func update(
        _ uid: Int64,
        text: String? = nil,
        person: String? = nil,
        prioA: String? = nil,
        prioB: String? = nil,
        dueDate: String? = nil
    ) {
        guard let idx = state.tasks.firstIndex(where: { $0.uid == uid }) else { return }
        if let text {
            let trimmed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            state.tasks[idx].text = trimmed
        }
        if let person {
            state.tasks[idx].person = person.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let prioA { state.tasks[idx].prioA = TodoJSON.prioA(prioA) }
        if let prioB { state.tasks[idx].prioB = TodoJSON.prioB(prioB) }
        if let dueDate { state.tasks[idx].dueDate = TodoJSON.isoDate(dueDate) }
        state.tasks[idx].updatedAt = TodoTime.nowIso()
        state.tasks[idx].changedBy = TodoAuthor.app
        state.revision += 1
        persistAndSync()
    }

    /// HTML Wieder öffnen: Original bleibt `completed` + `reopenedToUid`; offene Kopie mit neuem `uid`.
    @discardableResult
    func reopen(_ uid: Int64) -> Int64? {
        guard let idx = state.tasks.firstIndex(where: { $0.uid == uid }) else { return nil }
        let original = state.tasks[idx]
        guard TodoOrdering.canReopen(original) else { return nil }
        let now = TodoTime.nowIso()
        let reopenedAt = TodoTime.todayIso()
        let newUid = takeUid()
        var copy = original
        copy.uid = newUid
        copy.completed = false
        copy.completedDate = ""
        copy.reopenedFromUid = original.uid
        copy.reopenedToUid = nil
        copy.reopenedAt = reopenedAt
        copy.createdAt = now
        copy.updatedAt = now
        copy.changedBy = TodoAuthor.app
        state.tasks[idx].reopenedToUid = newUid
        state.tasks[idx].reopenedAt = reopenedAt
        state.tasks.append(copy)
        state.revision += 1
        persistAndSync()
        return newUid
    }

    func exportBackup() throws -> Data {
        try TodoCodec.encodeBackup(state)
    }

    func exportMarkdown(exportedAt: Date = Date(), timeZone: TimeZone = .current) throws -> Data {
        try TodoMarkdown.encode(state, exportedAt: exportedAt, timeZone: timeZone)
    }

    func exportCSV() throws -> Data {
        try TodoCSV.encode(state)
    }

    func importBackup(_ data: Data, append: Bool) throws {
        let incoming = try TodoCodec.decodeBackup(data)
        applyImported(incoming, append: append)
        lastError = nil
    }

    func importAny(_ data: Data, append: Bool) throws {
        let incoming = try TodoImport.decode(data)
        applyImported(incoming, append: append)
        lastError = nil
    }

    func importBackup(from url: URL, append: Bool) throws {
        let data = try IncomingJSON.data(from: url)
        try importBackup(data, append: append)
    }

    private func applyImported(_ incoming: TodoState, append: Bool) {
        if append {
            var merged = state
            merged.tasks.append(contentsOf: incoming.tasks)
            merged.nextUid = max(merged.nextUid, incoming.nextUid)
            state = TodoCodec.normalized(merged)
        } else {
            state = TodoCodec.normalized(incoming)
        }
        state.revision += 1
        persistAndSync()
    }

    private func takeUid() -> Int64 {
        var next = max(state.nextUid, 1)
        let used = Set(state.tasks.map(\.uid))
        while used.contains(next) { next += 1 }
        let uid = next
        state.nextUid = next + 1
        return uid
    }

#if os(iOS) || os(watchOS)
    private func hasNewerCompletions(local: TodoState, remote: TodoState) -> Bool {
        let remoteByUid = Dictionary(uniqueKeysWithValues: remote.tasks.map { ($0.uid, $0) })
        for task in local.tasks {
            let localAt = TodoMerge.timestamp(task.updatedAt)
            let remoteAt = TodoMerge.timestamp(remoteByUid[task.uid]?.updatedAt ?? "")
            if localAt > remoteAt { return true }
        }
        return false
    }
#endif

    private func persistAndSync() {
        persistQuietly()
        NotificationCenter.default.post(name: .todoStateDidChangeOnDisk, object: nil)
#if os(iOS) || os(watchOS)
        sync?.broadcast(state)
#endif
    }

    private func persistQuietly() {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            TodoPersistence.save(snapshot)
#if os(watchOS)
            WatchComplicationReload.todoTimelines()
#endif
        }
        TodoPersistence.save(state)
#if os(watchOS)
        WatchComplicationReload.todoTimelines()
#endif
    }
}
