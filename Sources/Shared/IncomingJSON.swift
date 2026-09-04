import Foundation

enum IncomingJSONKind: Equatable {
    case einkaufBackup
    case todoBackup
    case invalidJSON
    case unknown
}

enum IncomingJSONError: Error, LocalizedError, Equatable {
    case invalidJSON
    case unknownFormat

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "Die Datei ist kein gültiges JSON."
        case .unknownFormat: return "Die Datei ist weder ein Einkauf-Backup noch ein To-Do-Backup."
        }
    }
}

/// Router für Datei-/Share-JSON: `format`/`kind` zuerst, nie still ins falsche Store.
enum IncomingJSON {
    static func stripBOM(_ data: Data) -> Data {
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return data.dropFirst(3)
        }
        return data
    }

    static func data(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    static func classify(_ data: Data) -> IncomingJSONKind {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: stripBOM(data))
        } catch {
            return .invalidJSON
        }
        if looksLikeTodo(obj) { return .todoBackup }
        if let dict = obj as? [String: Any], BackupCodec.looksLikeBackup(dict) {
            return .einkaufBackup
        }
        return .unknown
    }

    /// `format == "todo-v3-json"`, nacktes Tasks-Array, oder `{tasks, nextUid}` ohne `stores`.
    static func looksLikeTodo(_ obj: Any) -> Bool {
        if obj is [Any] { return true }
        guard let dict = obj as? [String: Any] else { return false }
        if (dict["format"] as? String) == TodoCodec.backupFormat { return true }
        let kind = dict["kind"] as? String
        if kind == "einkauf-backup" || kind == "einkauf-local" { return false }
        if BackupCodec.looksLikeBackup(dict) { return false }
        let hasTasks = dict["tasks"] is [Any]
        let hasNextUid = dict["nextUid"] != nil
        let noStores = dict["stores"] == nil
        return hasTasks && hasNextUid && noStores
    }

    static func error(for kind: IncomingJSONKind) -> IncomingJSONError? {
        switch kind {
        case .invalidJSON: return .invalidJSON
        case .unknown: return .unknownFormat
        case .einkaufBackup, .todoBackup: return nil
        }
    }
}

enum TodoImportPrompt {
    static func message(currentCount: Int, incomingCount: Int) -> String {
        let current = currentCount == 1 ? "1 Aufgabe" : "\(currentCount) Aufgaben"
        let incoming = incomingCount == 1 ? "1 importierte Aufgabe" : "\(incomingCount) importierte Aufgaben"
        return "Aktuelle Liste (\(current)) und \(incoming) – ersetzen oder anhängen?"
    }
}
