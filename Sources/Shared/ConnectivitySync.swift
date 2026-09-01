import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Synchronisiert die Liste zwischen iPhone und Watch über WatchConnectivity.
/// Application Context hält den letzten Stand, `sendMessage` liefert Abhaken sofort,
/// `transferUserInfo` ist der Fallback wenn das Gegenstück nicht erreichbar ist.
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
        if let kind = payload["kind"] as? String, kind == "einkauf-toggle" {
            if let id = payload["id"] as? String, let done = payload["done"] as? Bool {
                let at = (payload["at"] as? Double) ?? Date.nowEpochMillis
                store?.applyRemoteToggle(id: id, done: done, at: at)
            }
            return
        }
        if let kind = payload["kind"] as? String, kind == "einkauf-pull" {
#if canImport(WatchConnectivity)
            if let state = store?.snapshotForPeer() {
                WatchSessionActor.shared.replySnapshot(state)
            }
#endif
            return
        }
        guard let blob = Self.extractBlob(payload) else { return }
        do {
            let incoming = try BackupCodec.decodeLocal(blob)
            store?.applyRemoteSnapshot(incoming)
        } catch {
            // Ungültige Payloads ignorieren.
        }
    }

    static func extractBlob(_ payload: [String: Any]) -> Data? {
        if let data = payload["blob"] as? Data { return data }
        if let s = payload["json"] as? String { return Data(s.utf8) }
        return nil
    }

    static func makePayload(_ state: AppState) -> [String: Any] {
        let blob = (try? BackupCodec.encodeLocal(state)) ?? Data()
        return [
            "kind": "einkauf-sync",
            "v": 1,
            "blob": blob
        ]
    }
}

#if canImport(WatchConnectivity)
/// WCSessionDelegate-Callbacks kommen nicht auf dem Main Actor — hier umleiten.
final class WatchSessionActor: NSObject, WCSessionDelegate {
    static let shared = WatchSessionActor()
    private weak var sync: ConnectivitySync?
    private var session: WCSession?

    func attach(_ sync: ConnectivitySync) {
        self.sync = sync
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func send(state: AppState) {
        guard let session, session.activationState == .activated else { return }
        let payload = ConnectivitySync.makePayload(state)
        try? session.updateApplicationContext(payload)
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

    func sendToggle(id: String, done: Bool, at: Double) {
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "kind": "einkauf-toggle",
            "id": id,
            "done": done,
            "at": at
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { [weak self] _ in
                if let sync = self?.sync {
                    Task { @MainActor in
                        if let state = sync.store?.snapshotForPeer() {
                            self?.send(state: state)
                        }
                    }
                }
            })
        }
        if let sync {
            Task { @MainActor in
                if let state = sync.store?.snapshotForPeer() {
                    try? session.updateApplicationContext(ConnectivitySync.makePayload(state))
                }
            }
        }
    }

    private func deliver(_ payload: [String: Any]) {
        Task { @MainActor in
            self.sync?.handleIncoming(payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        if !session.receivedApplicationContext.isEmpty {
            deliver(session.receivedApplicationContext)
        }
        Task { @MainActor in
            if let state = self.sync?.store?.snapshotForPeer() {
                self.send(state: state)
            }
        }
#if os(watchOS)
        if session.isReachable {
            session.sendMessage(["kind": "einkauf-pull"], replyHandler: { [weak self] reply in
                self?.deliver(reply)
            }, errorHandler: { _ in })
        }
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
            if let state = self.sync?.store?.snapshotForPeer() {
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
            if let state = self.sync?.store?.snapshotForPeer() {
                self.send(state: state)
            }
        }
    }
#endif

#if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        session.sendMessage(["kind": "einkauf-pull"], replyHandler: { [weak self] reply in
            self?.deliver(reply)
        }, errorHandler: { _ in
            Task { @MainActor in
                if let state = self.sync?.store?.snapshotForPeer() {
                    self.send(state: state)
                }
            }
        })
    }
#endif
}
#endif
