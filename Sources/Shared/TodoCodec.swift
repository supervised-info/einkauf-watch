import Foundation

enum TodoCodecError: Error, LocalizedError, Equatable {
    case notTodoLocal
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notTodoLocal: return "Keine gültige To-Do-Datei."
        case .invalidJSON: return "Die Datei ist kein gültiges JSON."
        }
    }
}

/// Lokales Envelope `kind: "todo-local"` — nie durch `BackupCodec` / Einkauf-Decode.
enum TodoCodec {
    static let localKind = "todo-local"
    static let version = 1

    static func encodeLocal(_ state: TodoState) throws -> Data {
        let normalized = normalized(state)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(TodoLocalEnvelope(kind: localKind, v: version, state: normalized))
    }

    static func decodeLocal(_ data: Data) throws -> TodoState {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TodoCodecError.invalidJSON
        }
        guard let dict = obj as? [String: Any] else { throw TodoCodecError.notTodoLocal }
        guard let kind = dict["kind"] as? String, kind == localKind else {
            throw TodoCodecError.notTodoLocal
        }
        do {
            let envelope = try JSONDecoder().decode(TodoLocalEnvelope.self, from: data)
            return normalized(envelope.state)
        } catch {
            throw TodoCodecError.invalidJSON
        }
    }

    /// Wie HTML `normalizeTasks`: fehlende/doppelte UIDs aus `nextUid`; `nextUid = max+1`.
    static func normalized(_ state: TodoState) -> TodoState {
        var next = state
        var used = Set<Int64>()
        var maxUid: Int64 = 0
        for i in next.tasks.indices {
            let uid = next.tasks[i].uid
            if uid > 0 && !used.contains(uid) {
                used.insert(uid)
                maxUid = max(maxUid, uid)
            } else {
                next.tasks[i].uid = 0
            }
            next.tasks[i].prioA = TodoJSON.prioA(next.tasks[i].prioA)
            next.tasks[i].prioB = TodoJSON.prioB(next.tasks[i].prioB)
            next.tasks[i].dueDate = TodoJSON.isoDate(next.tasks[i].dueDate)
            next.tasks[i].completedDate = TodoJSON.isoDate(next.tasks[i].completedDate)
            next.tasks[i].reopenedAt = TodoJSON.isoDate(next.tasks[i].reopenedAt)
            next.tasks[i].createdAt = TodoJSON.isoTimestamp(next.tasks[i].createdAt)
            next.tasks[i].updatedAt = TodoJSON.isoTimestamp(next.tasks[i].updatedAt)
            if next.tasks[i].reopenedFromUid ?? 0 <= 0 { next.tasks[i].reopenedFromUid = nil }
            if next.tasks[i].reopenedToUid ?? 0 <= 0 { next.tasks[i].reopenedToUid = nil }
        }
        var nextUid = max(next.nextUid, 1)
        nextUid = max(nextUid, maxUid + 1)
        for i in next.tasks.indices where next.tasks[i].uid == 0 {
            while used.contains(nextUid) { nextUid += 1 }
            next.tasks[i].uid = nextUid
            used.insert(nextUid)
            nextUid += 1
        }
        next.nextUid = nextUid
        return next
    }
}

private struct TodoLocalEnvelope: Codable {
    var kind: String
    var v: Int
    var state: TodoState
}
