import Foundation

/// Watch-Siri legt nur gesprochene Artikel-Strings in die App-Group-Queue.
/// Die Watch-App drain't sie auf dem live Store — kein volles Listen-Encode im Intent.
enum SiriPendingAdds {
    static let fileName = "einkauf-siri-pending.json"

    /// Neben `einkauf-local.json` im App-Group-Container (`group.net.tschelle.einkauf`).
    static var fileURL: URL {
        Persistence.fileURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    /// Rohtext nach optionalem Trigger-Prefix; leere Strings werden nicht gelegt.
    static func enqueue(_ speech: String, at url: URL? = nil) {
        let dest = url ?? fileURL
        let text = SpeechItemSplitter.strippingTriggerPrefix(speech)
        guard !text.isEmpty else { return }
        var queue = load(at: dest)
        queue.append(text)
        save(queue, at: dest)
    }

    /// Nimmt alle Einträge und leert die Datei. Fehlende Datei → `[]`.
    static func drain(at url: URL? = nil) -> [String] {
        let dest = url ?? fileURL
        let queue = load(at: dest)
        save([], at: dest)
        return queue
    }

    private static func load(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return items
    }

    private static func save(_ items: [String], at url: URL) {
        if items.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
