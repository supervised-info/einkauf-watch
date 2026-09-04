import Foundation

/// Datei-Import JSON / MD / CSV wie HTML `importFile`. Einkauf-Dateien werden abgelehnt.
/// Nicht in den Widget-Targets — die kompilieren nur `TodoCodec` (JSON).
enum TodoImport {
    static func decode(_ data: Data) throws -> TodoState {
        let stripped = IncomingJSON.stripBOM(data)
        if let obj = try? JSONSerialization.jsonObject(with: stripped) {
            if IncomingJSON.looksLikeTodo(obj) {
                return try TodoCodec.decodeBackup(data)
            }
            if let dict = obj as? [String: Any], TodoCodec.isEinkaufPayload(dict) {
                throw TodoCodecError.einkaufFile
            }
            throw TodoCodecError.notATodoBackup
        }
        guard let text = String(data: stripped, encoding: .utf8)
                ?? String(data: stripped, encoding: .isoLatin1) else {
            throw TodoCodecError.invalidText
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            throw TodoCodecError.invalidJSON
        }
        if looksLikeEinkaufMarkdown(text) {
            throw TodoCodecError.einkaufFile
        }
        if looksLikeEinkaufCSV(text) {
            throw TodoCodecError.einkaufFile
        }
        if looksLikeCSV(text) {
            return try TodoCSV.decode(text)
        }
        return try TodoMarkdown.decode(text)
    }

    /// HTML-CSV-Kopf enthält `Aufgabe` und `Prio A`.
    static func looksLikeCSV(_ text: String) -> Bool {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let header = first.replacingOccurrences(of: "\"", with: "").lowercased()
        if looksLikeEinkaufCSV(text) { return false }
        return header.contains("aufgabe") && header.contains("prio")
    }

    static func looksLikeEinkaufCSV(_ text: String) -> Bool {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let header = first.replacingOccurrences(of: "\"", with: "").lowercased()
        return header.contains("abteilung") || header.contains("einkauf-backup")
    }

    /// HTML-Einkauf: `# Einkauf — {Laden}` / `# Einkaufsliste`.
    static func looksLikeEinkaufMarkdown(_ text: String) -> Bool {
        for raw in text.split(whereSeparator: \.isNewline).prefix(24) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# Einkauf") { return true }
            if line.hasPrefix("# Einkaufsliste") { return true }
            if line.contains("einkauf-backup") { return true }
        }
        return false
    }
}
