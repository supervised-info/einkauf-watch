import Foundation

/// Watch-Siri legt nur gesprochene Artikel-Strings in die App-Group-Queue.
/// Die Watch-App drain't sie auf dem live Store — kein volles Listen-Encode im Intent.
/// Primär: `UserDefaults(suiteName: Persistence.appGroupId)` — zuverlässiger zwischen
/// Siri- und App-Prozess als eine Seitendatei. Datei nur Spiegel bzw. Fallback
/// im **App-Group-Container**, nie Application Support eines anderen Prozesses.
enum SiriPendingAdds {
    static let fileName = "einkauf-siri-pending.json"
    static let defaultsKey = "einkauf.siriPendingAdds"

    /// Genau die App-Group-ID — nicht ein anderer Suite-Name.
    static var suiteDefaults: UserDefaults? {
        UserDefaults(suiteName: Persistence.appGroupId)
    }

    /// Nur App-Group-Container, nie `Persistence.fileURL` (Application-Support-Fallback).
    static var fileURL: URL? {
        guard let container = Persistence.appGroupContainerURL else { return nil }
        let folder = container.appendingPathComponent("Einkauf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    /// Rohtext nach optionalem Trigger-Prefix; leere Strings werden nicht gelegt.
    /// `defaults` / `at` sind Test-Hooks; Produktion nutzt Suite + Datei-Spiegel.
    static func enqueue(_ speech: String, defaults: UserDefaults? = nil, at url: URL? = nil) {
        let text = SpeechItemSplitter.strippingTriggerPrefix(speech)
        guard !text.isEmpty else { return }

        if defaults != nil || url != nil {
            if let defaults {
                append(text, to: defaults)
            }
            if let url {
                var queue = loadFile(at: url)
                queue.append(text)
                saveFile(queue, at: url)
            }
            return
        }

        if let defaults = suiteDefaults {
            append(text, to: defaults)
            if let dest = fileURL {
                saveFile(defaults.stringArray(forKey: defaultsKey) ?? [text], at: dest)
            }
            return
        }

        if let dest = fileURL {
            var queue = loadFile(at: dest)
            queue.append(text)
            saveFile(queue, at: dest)
        }
    }

    /// Nimmt alle Einträge und leert Suite + Spiegel. Fehlende Queue → `[]`.
    static func drain(defaults: UserDefaults? = nil, at url: URL? = nil) -> [String] {
        if defaults != nil || url != nil {
            var queue: [String] = []
            if let defaults {
                queue = defaults.stringArray(forKey: defaultsKey) ?? []
                defaults.removeObject(forKey: defaultsKey)
                defaults.synchronize()
            }
            if let url {
                if queue.isEmpty {
                    queue = loadFile(at: url)
                }
                saveFile([], at: url)
            }
            return queue
        }

        var queue: [String] = []
        if let defaults = suiteDefaults {
            queue = defaults.stringArray(forKey: defaultsKey) ?? []
            defaults.removeObject(forKey: defaultsKey)
            defaults.synchronize()
        }
        if let dest = fileURL {
            if queue.isEmpty {
                queue = loadFile(at: dest)
            }
            saveFile([], at: dest)
        }
        return queue
    }

    private static func append(_ text: String, to defaults: UserDefaults) {
        var queue = defaults.stringArray(forKey: defaultsKey) ?? []
        queue.append(text)
        defaults.set(queue, forKey: defaultsKey)
        defaults.synchronize()
    }

    private static func loadFile(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return items
    }

    private static func saveFile(_ items: [String], at url: URL) {
        if items.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
