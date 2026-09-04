import Foundation

/// WatchConnectivity-`applicationContext` ist **ein** Dictionary — letzter `updateApplicationContext` gewinnt.
/// Deshalb liegen Einkauf und To-Do als Geschwister-Keys, nicht als zwei nacheinander geschriebene Payloads:
///
/// ```
/// {
///   "einkauf": { "kind": "einkauf-sync", "v": 1, "blob": Data },
///   "todo":    { "kind": "todo-sync",    "v": 1, "blob": Data }
/// }
/// ```
///
/// Beim Senden einer Domain: aktuellen Context lesen, nur diesen Key setzen, zurückschreiben.
/// Legacy: top-level `kind == "einkauf-sync"` (ohne Nested-Keys) gilt weiter als Einkauf-only.
///
/// `sendMessage` / `transferUserInfo` bleiben domain-spezifisch (`einkauf-*` bzw. `todo-*` auf Top-Level).
enum WatchSyncEnvelope {
    static let einkaufKey = "einkauf"
    static let todoKey = "todo"

    static let einkaufSyncKind = "einkauf-sync"
    static let einkaufToggleKind = "einkauf-toggle"
    static let einkaufPullKind = "einkauf-pull"

    static let todoSyncKind = "todo-sync"
    static let todoToggleKind = "todo-toggle"
    static let todoPullKind = "todo-pull"

    /// Liest den aktuellen Application Context, hebt Legacy-`einkauf-sync` an und ersetzt nur `domain`.
    static func merging(_ current: [String: Any], domain: String, payload: [String: Any]) -> [String: Any] {
        var next = normalizedContext(current)
        next[domain] = payload
        return next
    }

    /// Nested `{einkauf, todo}` plus Legacy-Top-Level-`kind: einkauf-sync`.
    static func normalizedContext(_ current: [String: Any]) -> [String: Any] {
        var next: [String: Any] = [:]
        if let nested = dictionary(current[einkaufKey]) {
            next[einkaufKey] = nested
        } else if isEinkaufKind(current["kind"] as? String) {
            next[einkaufKey] = strippedDomainPayload(current)
        }
        if let nested = dictionary(current[todoKey]) {
            next[todoKey] = nested
        } else if isTodoKind(current["kind"] as? String) {
            next[todoKey] = strippedDomainPayload(current)
        }
        return next
    }

    /// Top-Level `einkauf-*` **oder** nested `einkauf` **oder** Legacy `kind: einkauf-sync`.
    static func einkaufPayload(from payload: [String: Any]) -> [String: Any]? {
        if isEinkaufKind(payload["kind"] as? String) { return payload }
        if let nested = dictionary(payload[einkaufKey]) { return nested }
        return nil
    }

    /// Top-Level `todo-*` **oder** nested `todo`.
    static func todoPayload(from payload: [String: Any]) -> [String: Any]? {
        if isTodoKind(payload["kind"] as? String) { return payload }
        if let nested = dictionary(payload[todoKey]) { return nested }
        return nil
    }

    /// Messages mit Top-Level-`kind` gehen nur in eine Domain; gemergter Context (kein `kind`) kann beide liefern.
    static func splitIncoming(_ payload: [String: Any]) -> (einkauf: [String: Any]?, todo: [String: Any]?) {
        if isEinkaufKind(payload["kind"] as? String) {
            return (payload, nil)
        }
        if isTodoKind(payload["kind"] as? String) {
            return (nil, payload)
        }
        return (einkaufPayload(from: payload), todoPayload(from: payload))
    }

    static func extractBlob(_ payload: [String: Any]) -> Data? {
        if let data = payload["blob"] as? Data { return data }
        if let s = payload["json"] as? String { return Data(s.utf8) }
        return nil
    }

    /// WCSession plist: `Int64` kommt oft als `NSNumber`.
    static func uid(from payload: [String: Any]) -> Int64? {
        let raw = payload["uid"]
        if let v = raw as? Int64, v > 0 { return v }
        if let v = raw as? Int, v > 0 { return Int64(v) }
        if let v = raw as? NSNumber {
            let i = v.int64Value
            return i > 0 ? i : nil
        }
        if let v = raw as? Double {
            let i = Int64(v)
            return i > 0 && Double(i) == v ? i : nil
        }
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = Int64(trimmed), v > 0 else { return nil }
            return v
        }
        return nil
    }

    static func toggleAt(from payload: [String: Any]) -> String {
        if let s = payload["at"] as? String { return TodoJSON.isoTimestamp(s) }
        return ""
    }

    /// UI-Filter, nicht im Todo-Blob / Backup. Leer = Alle.
    static func currentListId(from payload: [String: Any]) -> String? {
        guard let raw = payload["currentListId"] else { return nil }
        if let s = raw as? String { return TodoListFilter.resolved(s) }
        return nil
    }

    static func isEinkaufKind(_ kind: String?) -> Bool {
        guard let kind else { return false }
        return kind == einkaufSyncKind || kind == einkaufToggleKind || kind == einkaufPullKind
    }

    static func isTodoKind(_ kind: String?) -> Bool {
        guard let kind else { return false }
        return kind == todoSyncKind || kind == todoToggleKind || kind == todoPullKind
    }

    private static func strippedDomainPayload(_ current: [String: Any]) -> [String: Any] {
        var payload: [String: Any] = [:]
        for key in ["kind", "v", "blob", "json", "currentListId"] {
            if let value = current[key] { payload[key] = value }
        }
        return payload
    }

    static func dictionary(_ value: Any?) -> [String: Any]? {
        if let d = value as? [String: Any] { return d }
        if let d = value as? NSDictionary {
            var out: [String: Any] = [:]
            d.forEach { key, val in
                if let k = key as? String { out[k] = val }
            }
            return out.isEmpty ? nil : out
        }
        return nil
    }
}

/// Listenstruktur folgt höherer `revision`; `completed` je Task über `updatedAt`.
/// Ohne Stempel: erledigt gewinnt. Nicht `listRevision` von Einkauf.
enum TodoMerge {
    static func merge(local: TodoState, remote: TodoState) -> TodoState {
        let base: TodoState
        let other: TodoState
        if remote.revision > local.revision {
            base = remote
            other = local
        } else {
            base = local
            other = remote
        }
        let otherByUid = Dictionary(uniqueKeysWithValues: other.tasks.map { ($0.uid, $0) })
        var tasks = base.tasks
        for i in tasks.indices {
            if let incoming = otherByUid[tasks[i].uid] {
                tasks[i] = pickCompleted(base: tasks[i], other: incoming)
            }
        }
        var result = base
        result.tasks = tasks
        result.revision = max(local.revision, remote.revision)
        let maxUid = tasks.map(\.uid).max() ?? 0
        result.nextUid = max(local.nextUid, remote.nextUid, maxUid + 1)
        return TodoCodec.normalized(result)
    }

    static func pickCompleted(base: TodoTask, other: TodoTask) -> TodoTask {
        var task = base
        let a = timestamp(base.updatedAt)
        let b = timestamp(other.updatedAt)
        if b > a {
            task.completed = other.completed
            task.completedDate = other.completedDate
            task.updatedAt = other.updatedAt
        } else if b == a && a == 0 && other.completed != base.completed {
            task.completed = base.completed || other.completed
            if task.completed {
                if task.completedDate.isEmpty {
                    task.completedDate = other.completedDate
                }
            } else {
                task.completedDate = ""
            }
        }
        return task
    }

    static func timestamp(_ iso: String) -> TimeInterval {
        let s = TodoJSON.isoTimestamp(iso)
        guard !s.isEmpty else { return 0 }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d.timeIntervalSince1970 }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let d = basic.date(from: s) { return d.timeIntervalSince1970 }
        return 0
    }
}
