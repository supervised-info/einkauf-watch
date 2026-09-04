import Foundation
import Combine

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var state: TodoState
    @Published var lastError: String?

    private var saveTask: Task<Void, Never>?
    private var diskObserver: NSObjectProtocol?

    /// `enableSync` ist Phase-2 ungenutzt (kein WatchConnectivity für To-Do).
    init(state: TodoState? = nil, enableSync: Bool = true) {
        _ = enableSync
        if let state {
            self.state = TodoCodec.normalized(state)
        } else {
            self.state = TodoPersistence.load() ?? .empty
        }
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
        persist()
        return uid
    }

    func toggle(_ uid: Int64) {
        guard let idx = state.tasks.firstIndex(where: { $0.uid == uid }) else { return }
        state.tasks[idx].completed.toggle()
        state.tasks[idx].completedDate = state.tasks[idx].completed ? TodoTime.todayIso() : ""
        state.tasks[idx].updatedAt = TodoTime.nowIso()
        state.revision += 1
        persist()
    }

    func delete(_ uid: Int64) {
        let before = state.tasks.count
        state.tasks.removeAll { $0.uid == uid }
        guard state.tasks.count != before else { return }
        state.revision += 1
        persist()
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
        persist()
    }

    private func takeUid() -> Int64 {
        var next = max(state.nextUid, 1)
        let used = Set(state.tasks.map(\.uid))
        while used.contains(next) { next += 1 }
        let uid = next
        state.nextUid = next + 1
        return uid
    }

    private func persist() {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            TodoPersistence.save(snapshot)
        }
        TodoPersistence.save(state)
        NotificationCenter.default.post(name: .todoStateDidChangeOnDisk, object: nil)
    }
}
