import Foundation

/// Textdatei für den Einkauf-Overflow **Liste hinzufügen**: eine Zeile = ein Artikel.
/// Kein `SpeechItemSplitter` — Kommas und „und“ bleiben im Namen (z. B. „Milch 1,5 %“).
enum ShoppingListImport {
    struct Outcome: Equatable {
        var added: Int
        var skippedDuplicates: Int
    }

    static func allowedPathExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "txt", "md":
            return true
        default:
            return false
        }
    }

    static func lines(from data: Data) -> [String] {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = Data(bytes.dropFirst(3))
        }
        return lines(from: String(decoding: bytes, as: UTF8.self))
    }

    static func lines(from text: String) -> [String] {
        var source = text
        if source.first == "\u{FEFF}" {
            source.removeFirst()
        }
        return source
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Dieselbe Namensform wie getipptes Hinzufügen: Whitespace falten, trimmen.
    static func normalizedName(_ rawName: String) -> String? {
        let name = rawName.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Neue Zeilen gegen vorhandene Namen. Getipptes Hinzufügen filtert nicht;
    /// hier zählt der normalisierte Name ohne Groß-/Kleinschreibung.
    static func select(lines: [String], existingNames: [String]) -> (names: [String], skippedDuplicates: Int) {
        var seen = Set(existingNames.compactMap { normalizedName($0)?.lowercased() })
        var fresh: [String] = []
        var skipped = 0
        fresh.reserveCapacity(lines.count)
        for raw in lines {
            guard let name = normalizedName(raw) else { continue }
            let key = name.lowercased()
            if seen.contains(key) {
                skipped += 1
                continue
            }
            seen.insert(key)
            fresh.append(name)
        }
        return (fresh, skipped)
    }

    static func confirmation(added: Int, skippedDuplicates: Int) -> String {
        let addedText: String
        switch added {
        case 0:
            addedText = "Nichts hinzugefügt."
        case 1:
            addedText = "1 Artikel hinzugefügt."
        default:
            addedText = "\(added) Artikel hinzugefügt."
        }
        guard skippedDuplicates > 0 else { return addedText }
        let skippedText = skippedDuplicates == 1
            ? "1 bereits vorhanden."
            : "\(skippedDuplicates) bereits vorhanden."
        return "\(addedText) \(skippedText)"
    }
}
