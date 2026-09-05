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

    /// Ausgewählte Zeilen zum Import; Rest bleibt in `inbox.txt`.
    static func partition(items: [String], selectedOffsets: Set<Int>) -> InboxRetrievePartition {
        var selected: [String] = []
        var remainder: [String] = []
        selected.reserveCapacity(selectedOffsets.count)
        remainder.reserveCapacity(max(0, items.count - selectedOffsets.count))
        for (index, item) in items.enumerated() {
            if selectedOffsets.contains(index) {
                selected.append(item)
            } else {
                remainder.append(item)
            }
        }
        return InboxRetrievePartition(selected: selected, remainder: remainder)
    }

    /// UTF-8-Text für die Datei: eine Zeile pro Artikel; leer wie `Data()` wenn nichts bleibt.
    static func fileText(remainingItems: [String]) -> String {
        if remainingItems.isEmpty { return "" }
        return remainingItems.joined(separator: "\n") + "\n"
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

    static func noneSelectedMessage() -> String {
        "Nichts ausgewählt."
    }
}

struct InboxRetrievePartition: Equatable {
    var selected: [String]
    var remainder: [String]
}
