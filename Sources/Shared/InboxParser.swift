import Foundation

/// Zeilenparser für die geteilte iCloud-Drive-Datei `Einkauf-Inbox/inbox.txt`.
/// Die Datei hält nur noch nicht abgeholte Artikel — eine Zeile pro Artikel, kein Statusfeld.
/// Leerzeilen und `# …`-Kommentare (inkl. optionalem Header `# einkauf-inbox v1`) werden übersprungen.
enum InboxParser {
    static func items(from data: Data) -> [String] {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = Data(bytes.dropFirst(3))
        }
        return items(from: String(decoding: bytes, as: UTF8.self))
    }

    static func items(from text: String) -> [String] {
        var source = text
        if source.first == "\u{FEFF}" {
            source.removeFirst()
        }
        return source
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// `SpeechItemSplitter` trennt an Zeilenumbruch, Komma, Semikolon, ` und `, ` sowie `.
    static func speechText(from items: [String]) -> String {
        items.joined(separator: "\n")
    }

    static func retrieveConfirmation(addedCount: Int) -> String {
        switch addedCount {
        case 0:
            return "Nichts abzuholen."
        case 1:
            return "1 Artikel übernommen."
        default:
            return "\(addedCount) Artikel übernommen."
        }
    }
}
