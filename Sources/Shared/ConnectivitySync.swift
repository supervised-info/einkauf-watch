import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Synchronisiert die Liste zwischen iPhone und Watch über WatchConnectivity.
/// Application Context hält den letzten Stand **beider** Domains (siehe `WatchSyncEnvelope`),
/// `sendMessage` liefert Abhaken sofort, `transferUserInfo` ist der Fallback wenn das Gegenstück nicht erreichbar ist.
@MainActor
final class ConnectivitySync: NSObject {
    weak var store: ShoppingStore?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
#if canImport(WatchConnectivity)
        WatchSessionActor.shared.attach(self)
#endif
    }

    func broadcast(_ state: AppState) {
#if canImport(WatchConnectivity)
        WatchSessionActor.shared.send(state: state)
#endif
    }

    func broadcastToggle(id: String, done: Bool, at: Double, state: AppState) {
#if canImport(WatchConnectivity)
        WatchSessionActor.shared.sendToggle(id: id, done: done, at: at)
        WatchSessionActor.shared.send(state: state)
#endif
    }

    func handleIncoming(_ payload: [String: Any]) {
        if let kind = payload["kind"] as? String, kind == WatchSyncEnvelope.einkaufToggleKind {
            if let id = payload["id"] as? String, let done = payload["done"] as? Bool {
                let at = (payload["at"] as? Double) ?? Date.nowEpochMillis
                store?.applyRemoteToggle(id: id, done: done, at: at)
            }
            return
        }
        if let kind = payload["kind"] as? String, kind == WatchSyncEnvelope.einkaufPullKind {
#if canImport(WatchConnectivity)
            if let state = store?.snapshotForPeer() {
                WatchSessionActor.shared.replySnapshot(state)
            }
#endif
            return
        }
        if let kind = payload["kind"] as? String, kind != WatchSyncEnvelope.einkaufSyncKind {
            return
        }
        guard let blob = Self.extractBlob(payload) else { return }
        do {
            let incoming = try BackupCodec.decodeLocal(blob)
            store?.applyRemoteSnapshot(incoming)
        } catch {
            // Ungültige Payloads ignorieren (inkl. To-Do-Blobs).
        }
    }

    /// Nur Encode/Decode, kein Store-Zugriff — muss von WCSessionDelegate
    /// (nicht MainActor) synchron aufrufbar sein (Swift 6).
    nonisolated static func extractBlob(_ payload: [String: Any]) -> Data? {
        WatchSyncEnvelope.extractBlob(payload)
    }

    nonisolated static func makePayload(_ state: AppState) -> [String: Any] {
        let blob = (try? BackupCodec.encodeLocal(state)) ?? Data()
        return [
            "kind": WatchSyncEnvelope.einkaufSyncKind,
            "v": 1,
            "blob": blob
        ]
    }
}

/// To-Do-Sync analog `ConnectivitySync`. Blob = `kind: todo-local` über `TodoCodec`.
@MainActor
final class TodoConnectivitySync: NSObject {
    weak var store: TodoStore?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
#if canImport(WatchConnectivity)
        WatchSessionActor.shared.attachTodo(self)
#endif
    }

    func broadcast(_ state: TodoState) {
#if canImport(WatchConnectivity)
        WatchSessionActor.shared.sendTodo(state: state)
#endif
    }

    func broadcastToggle(uid: Int64, completed: Bool, at: String, state: TodoState) {
#if canImport(WatchConnectivity)
        WatchSessionActor.shared.sendTodoToggle(uid: uid, completed: completed, at: at)
        WatchSessionActor.shared.sendTodo(state: state)
#endif
    }

    func handleIncoming(_ payload: [String: Any]) {
        if let kind = payload["kind"] as? String, kind == WatchSyncEnvelope.todoToggleKind {
            if let uid = WatchSyncEnvelope.uid(from: payload), let completed = payload["completed"] as? Bool {
                let at = WatchSyncEnvelope.toggleAt(from: payload)
                store?.applyRemoteToggle(uid: uid, completed: completed, at: at)
            }
            return
        }
        if let kind = payload["kind"] as? String, kind == WatchSyncEnvelope.todoPullKind {
#if canImport(WatchConnectivity)
            if let state = store?.snapshotForPeer() {
                WatchSessionActor.shared.replyTodoSnapshot(state)
            }
#endif
            return
        }
        guard let kind = payload["kind"] as? String, kind == WatchSyncEnvelope.todoSyncKind else { return }
        guard let blob = WatchSyncEnvelope.extractBlob(payload) else { return }
        do {
            let incoming = try TodoCodec.decodeLocal(blob)
            store?.applyRemoteSnapshot(incoming)
        } catch {
            // Ungültige Payloads ignorieren (inkl. Einkauf-Blobs).
        }
    }

    nonisolated static func makePayload(_ state: TodoState) -> [String: Any] {
        let blob = (try? TodoCodec.encodeLocal(state)) ?? Data()
        return [
            "kind": WatchSyncEnvelope.todoSyncKind,
            "v": 1,
            "blob": blob
        ]
    }
}

#if canImport(WatchConnectivity)
/// WCSessionDelegate-Callbacks kommen nicht auf dem Main Actor — hier umleiten.
/// Ein Delegate: Einkauf **und** To-Do. Application Context immer mergen, nie eine Domain überschreiben.
final class WatchSessionActor: NSObject, WCSessionDelegate {
    static let shared = WatchSessionActor()
    private weak var einkaufSync: ConnectivitySync?
    private weak var todoSync: TodoConnectivitySync?
    private var session: WCSession?

    func attach(_ sync: ConnectivitySync) {
        self.einkaufSync = sync
        ensureSession()
        if session?.activationState == .activated {
            flushEinkauf()
        }
    }

    func attachTodo(_ sync: TodoConnectivitySync) {
        self.todoSync = sync
        ensureSession()
        if session?.activationState == .activated {
            flushTodo()
        }
    }

    private func ensureSession() {
        guard WCSession.isSupported() else { return }
        if session != nil { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func send(state: AppState) {
        guard let session, session.activationState == .activated else { return }
        let payload = ConnectivitySync.makePayload(state)
        updateMergedApplicationContext(domain: WatchSyncEnvelope.einkaufKey, payload: payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                self?.deliver(reply)
            }, errorHandler: { [weak session] _ in
                session?.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    func sendTodo(state: TodoState) {
        guard let session, session.activationState == .activated else { return }
        let payload = TodoConnectivitySync.makePayload(state)
        updateMergedApplicationContext(domain: WatchSyncEnvelope.todoKey, payload: payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                self?.deliver(reply)
            }, errorHandler: { [weak session] _ in
                session?.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    func replySnapshot(_ state: AppState) {
        send(state: state)
    }

    func replyTodoSnapshot(_ state: TodoState) {
        sendTodo(state: state)
    }

    func sendToggle(id: String, done: Bool, at: Double) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "kind": WatchSyncEnvelope.einkaufToggleKind,
            "id": id,
            "done": done,
            "at": at
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { [weak self] _ in
                if let sync = self?.einkaufSync {
                    Task { @MainActor in
                        if let state = sync.store?.snapshotForPeer() {
                            self?.send(state: state)
                        }
                    }
                }
            })
        }
        if let sync = einkaufSync {
            Task { @MainActor in
                if let state = sync.store?.snapshotForPeer() {
                    self.updateMergedApplicationContext(
                        domain: WatchSyncEnvelope.einkaufKey,
                        payload: ConnectivitySync.makePayload(state)
                    )
                }
            }
        }
    }

    func sendTodoToggle(uid: Int64, completed: Bool, at: String) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "kind": WatchSyncEnvelope.todoToggleKind,
            "uid": NSNumber(value: uid),
            "completed": completed,
            "at": at
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { [weak self] _ in
                if let sync = self?.todoSync {
                    Task { @MainActor in
                        if let state = sync.store?.snapshotForPeer() {
                            self?.sendTodo(state: state)
                        }
                    }
                }
            })
        }
        if let sync = todoSync {
            Task { @MainActor in
                if let state = sync.store?.snapshotForPeer() {
                    self.updateMergedApplicationContext(
                        domain: WatchSyncEnvelope.todoKey,
                        payload: TodoConnectivitySync.makePayload(state)
                    )
                }
            }
        }
    }

    private func updateMergedApplicationContext(domain: String, payload: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        let merged = WatchSyncEnvelope.merging(session.applicationContext, domain: domain, payload: payload)
        try? session.updateApplicationContext(merged)
    }

    private func deliver(_ payload: [String: Any]) {
        let split = WatchSyncEnvelope.splitIncoming(payload)
        Task { @MainActor in
            if let einkauf = split.einkauf {
                self.einkaufSync?.handleIncoming(einkauf)
            }
            if let todo = split.todo {
                self.todoSync?.handleIncoming(todo)
            }
        }
    }

    private func flushEinkauf() {
        if let session, !session.receivedApplicationContext.isEmpty {
            deliver(session.receivedApplicationContext)
        }
        Task { @MainActor in
            if let state = self.einkaufSync?.store?.snapshotForPeer() {
                self.send(state: state)
            }
        }
#if os(watchOS)
        pullEinkaufIfReachable()
#endif
    }

    private func flushTodo() {
        if let session, !session.receivedApplicationContext.isEmpty {
            deliver(session.receivedApplicationContext)
        }
        Task { @MainActor in
            if let state = self.todoSync?.store?.snapshotForPeer() {
                self.sendTodo(state: state)
            }
        }
#if os(watchOS)
        pullTodoIfReachable()
#endif
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        if !session.receivedApplicationContext.isEmpty {
            deliver(session.receivedApplicationContext)
        }
        Task { @MainActor in
            if let state = self.einkaufSync?.store?.snapshotForPeer() {
                self.send(state: state)
            }
            if let state = self.todoSync?.store?.snapshotForPeer() {
                self.sendTodo(state: state)
            }
        }
#if os(watchOS)
        pullEinkaufIfReachable()
        pullTodoIfReachable()
#endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        deliver(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        deliver(message)
        Task { @MainActor in
            let split = WatchSyncEnvelope.splitIncoming(message)
            if split.todo != nil {
                if let state = self.todoSync?.store?.snapshotForPeer() {
                    replyHandler(TodoConnectivitySync.makePayload(state))
                } else {
                    replyHandler([:])
                }
            } else if let state = self.einkaufSync?.store?.snapshotForPeer() {
                replyHandler(ConnectivitySync.makePayload(state))
            } else {
                replyHandler([:])
            }
        }
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            if let state = self.einkaufSync?.store?.snapshotForPeer() {
                self.send(state: state)
            }
            if let state = self.todoSync?.store?.snapshotForPeer() {
                self.sendTodo(state: state)
            }
        }
    }
#endif

#if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        pullEinkaufIfReachable()
        pullTodoIfReachable()
    }

    private func pullEinkaufIfReachable() {
        guard let session, session.isReachable else { return }
        session.sendMessage(["kind": WatchSyncEnvelope.einkaufPullKind], replyHandler: { [weak self] reply in
            self?.deliver(reply)
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                if let state = self?.einkaufSync?.store?.snapshotForPeer() {
                    self?.send(state: state)
                }
            }
        })
    }

    private func pullTodoIfReachable() {
        guard let session, session.isReachable else { return }
        session.sendMessage(["kind": WatchSyncEnvelope.todoPullKind], replyHandler: { [weak self] reply in
            self?.deliver(reply)
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                if let state = self?.todoSync?.store?.snapshotForPeer() {
                    self?.sendTodo(state: state)
                }
            }
        })
    }
#endif
}
#endif
