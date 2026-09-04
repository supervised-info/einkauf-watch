import Foundation

enum TodoCodecError: Error, LocalizedError, Equatable {
    case notTodoLocal
    case invalidJSON
    case invalidText
    case notATodoBackup
    case einkaufFile
    case empty
    case nothingToExport

    var errorDescription: String? {
        switch self {
        case .notTodoLocal: return "Keine gültige To-Do-Datei."
        case .invalidJSON: return "Die Datei ist kein gültiges JSON."
        case .invalidText: return "Die Datei konnte nicht gelesen werden."
        case .notATodoBackup: return "Keine gültige To-Do-Backup-Datei."
        case .einkaufFile: return "Das ist eine Einkauf-Datei, kein To-Do-Backup."
        case .empty: return "Keine Aufgaben gefunden."
        case .nothingToExport: return "Keine Aufgaben vorhanden."
        }
    }
}

/// Lokales Envelope `kind: "todo-local"` und HTML-Brücke `format: "todo-v3-json"`.
/// Nie durch `BackupCodec` / Einkauf-Decode.
enum TodoCodec {
    static let localKind = "todo-local"
    static let backupFormat = "todo-v3-json"
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

    /// HTML-Brücke: `{ format: "todo-v3-json", exportedAt, nextUid, tasks }` ohne `kind` / `revision`.
    static func encodeBackup(_ state: TodoState, exportedAt: Date = Date()) throws -> Data {
        let normalized = normalized(state)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            TodoV3Envelope(
                format: backupFormat,
                exportedAt: TodoTime.nowIso(exportedAt),
                nextUid: normalized.nextUid,
                tasks: normalized.tasks,
                lists: normalized.lists
            )
        )
    }

    /// HTML-Import: Objekt `{tasks, nextUid}` (Format optional) **oder** nacktes Tasks-Array.
    /// Extra-Felder werden ignoriert. `einkauf-backup` / `einkauf-local` werden abgelehnt.
    static func decodeBackup(_ data: Data) throws -> TodoState {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: IncomingJSON.stripBOM(data))
        } catch {
            throw TodoCodecError.invalidJSON
        }
        if let dict = obj as? [String: Any] {
            let hasFormat = (dict["format"] as? String) == backupFormat
            let hasTasks = dict["tasks"] is [Any]
            if !hasFormat {
                if isEinkaufPayload(dict) {
                    throw TodoCodecError.einkaufFile
                }
                guard hasTasks else { throw TodoCodecError.notATodoBackup }
            }
            do {
                let envelope = try JSONDecoder().decode(TodoV3Envelope.self, from: IncomingJSON.stripBOM(data))
                return try makeImportedState(tasks: envelope.tasks, nextUid: envelope.nextUid, lists: envelope.lists)
            } catch let error as TodoCodecError {
                throw error
            } catch {
                throw TodoCodecError.invalidJSON
            }
        }
        if let _ = obj as? [Any] {
            do {
                let tasks = try JSONDecoder().decode([TodoTask].self, from: IncomingJSON.stripBOM(data))
                return try makeImportedState(tasks: tasks, nextUid: 1)
            } catch {
                throw TodoCodecError.invalidJSON
            }
        }
        throw TodoCodecError.notATodoBackup
    }

    static func isEinkaufPayload(_ dict: [String: Any]) -> Bool {
        if let kind = dict["kind"] as? String, kind.hasPrefix("einkauf-") { return true }
        return BackupCodec.looksLikeBackup(dict)
    }

    static func makeImportedState(
        tasks: [TodoTask],
        nextUid: Int64 = 1,
        lists: [TodoNamedList] = []
    ) throws -> TodoState {
        let kept = tasks.filter { !$0.text.isEmpty }
        guard !kept.isEmpty else { throw TodoCodecError.empty }
        return normalized(TodoState(tasks: kept, nextUid: max(nextUid, 1), revision: 0, lists: lists))
    }

    /// Wie HTML `normalizeTasks`: fehlende/doppelte UIDs aus `nextUid`; `nextUid = max+1`.
    static func normalized(_ state: TodoState) -> TodoState {
        var next = state
        next.lists = normalizedLists(next.lists)
        let validListIds = Set(next.lists.map(\.id))
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
            if let listId = TodoJSON.normalizedListId(next.tasks[i].listId), validListIds.contains(listId) {
                next.tasks[i].listId = listId
            } else {
                next.tasks[i].listId = nil
            }
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

    static func normalizedLists(_ lists: [TodoNamedList]) -> [TodoNamedList] {
        var used = Set<String>()
        var result: [TodoNamedList] = []
        for list in lists {
            var id = list.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if id.isEmpty {
                id = TodoJSON.newListId()
            }
            if used.contains(id) { continue }
            used.insert(id)
            result.append(TodoNamedList(id: id, name: name))
        }
        return result
    }

    static func mergeLists(_ local: [TodoNamedList], _ incoming: [TodoNamedList]) -> [TodoNamedList] {
        var byId: [String: TodoNamedList] = [:]
        var order: [String] = []
        for list in normalizedLists(local) + normalizedLists(incoming) {
            if byId[list.id] == nil {
                order.append(list.id)
                byId[list.id] = list
            }
        }
        return order.compactMap { byId[$0] }
    }
}

private struct TodoLocalEnvelope: Codable {
    var kind: String
    var v: Int
    var state: TodoState
}

private struct TodoV3Envelope: Codable {
    var format: String
    var exportedAt: String
    var nextUid: Int64
    var tasks: [TodoTask]
    var lists: [TodoNamedList]

    enum CodingKeys: String, CodingKey {
        case format, exportedAt, nextUid, tasks, lists
    }

    init(format: String, exportedAt: String, nextUid: Int64, tasks: [TodoTask], lists: [TodoNamedList]) {
        self.format = format
        self.exportedAt = exportedAt
        self.nextUid = nextUid
        self.tasks = tasks
        self.lists = lists
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? ""
        exportedAt = try c.decodeIfPresent(String.self, forKey: .exportedAt) ?? ""
        if let n = try c.decodeIfPresent(Int64.self, forKey: .nextUid) {
            nextUid = max(1, n)
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .nextUid) {
            nextUid = Int64(max(1, n))
        } else {
            nextUid = 1
        }
        tasks = try c.decodeIfPresent([TodoTask].self, forKey: .tasks) ?? []
        lists = try c.decodeIfPresent([TodoNamedList].self, forKey: .lists) ?? []
    }
}
