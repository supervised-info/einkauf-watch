import Foundation

/// Snapshot eines endgültig gelöschten **erledigten** Eintrags.
/// Ein Eintrag = ein Item; Bulk-Deletes schreiben mehrere Einträge (Burst-`archivedAt` ok).
struct ItemArchiveEntry<Snapshot: Codable>: Codable, Equatable, Sendable where Snapshot: Equatable & Sendable {
    var archivedAt: String
    var item: Snapshot
}

/// `{ "v": 1, "entries": [ … ] }` — History nur anhängen, nie ersetzen.
struct ItemArchiveFile<Snapshot: Codable>: Codable, Equatable, Sendable where Snapshot: Equatable & Sendable {
    var v: Int
    var entries: [ItemArchiveEntry<Snapshot>]

    static var empty: ItemArchiveFile { ItemArchiveFile(v: 1, entries: []) }

    enum CodingKeys: String, CodingKey {
        case v, entries
    }

    init(v: Int, entries: [ItemArchiveEntry<Snapshot>]) {
        self.v = v
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        entries = try c.decodeIfPresent([ItemArchiveEntry<Snapshot>].self, forKey: .entries) ?? []
    }
}

/// App-Group-Archive neben `einkauf-local.json` / `todo-local.json`.
/// Nur beim endgültigen Löschen erledigter Einträge; Abhaken schreibt nichts.
enum CompletedItemArchive {
    static let version = 1
    static let einkaufFileName = "einkauf-archiv.json"
    static let todoFileName = "todo-archiv.json"

    static var folderURL: URL {
        Persistence.fileURL.deletingLastPathComponent()
    }

    static var einkaufFileURL: URL {
        folderURL.appendingPathComponent(einkaufFileName)
    }

    static var todoFileURL: URL {
        folderURL.appendingPathComponent(todoFileName)
    }

    static func loadEinkauf() -> ItemArchiveFile<Item> {
        load(from: einkaufFileURL, as: Item.self, includeInternal: true)
    }

    static func loadTodo() -> ItemArchiveFile<TodoTask> {
        load(from: todoFileURL, as: TodoTask.self, includeInternal: false)
    }

    static func appendEinkauf(_ items: [Item], at date: Date = Date()) {
        let done = items.filter(\.done)
        guard !done.isEmpty else { return }
        append(done, to: einkaufFileURL, as: Item.self, includeInternal: true, at: date)
    }

    static func appendTodo(_ tasks: [TodoTask], at date: Date = Date()) {
        let done = tasks.filter(\.completed)
        guard !done.isEmpty else { return }
        append(done, to: todoFileURL, as: TodoTask.self, includeInternal: false, at: date)
    }

    static func encodeEinkauf() throws -> Data {
        try encode(loadEinkauf(), includeInternal: true)
    }

    static func encodeTodo() throws -> Data {
        try encode(loadTodo(), includeInternal: false)
    }

    static func iso8601(_ date: Date = Date()) -> String {
        TodoTime.nowIso(date)
    }

    private static func append<Snapshot: Codable & Equatable & Sendable>(
        _ snapshots: [Snapshot],
        to url: URL,
        as type: Snapshot.Type,
        includeInternal: Bool,
        at date: Date
    ) {
        guard !snapshots.isEmpty else { return }
        guard var file = loadForAppend(from: url, as: type, includeInternal: includeInternal) else { return }
        let stamp = iso8601(date)
        file.v = version
        file.entries.append(contentsOf: snapshots.map { ItemArchiveEntry(archivedAt: stamp, item: $0) })
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encode(file, includeInternal: includeInternal).write(to: url, options: [.atomic])
        } catch {
            // Archivfehler sollen Löschen nicht crashen.
        }
    }

    /// Fehlende/leere Datei → leeres Archiv. Ungültiges JSON nicht überschreiben.
    private static func loadForAppend<Snapshot: Codable & Equatable & Sendable>(
        from url: URL,
        as type: Snapshot.Type,
        includeInternal: Bool
    ) -> ItemArchiveFile<Snapshot>? {
        if !FileManager.default.fileExists(atPath: url.path) {
            return .empty
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.isEmpty { return .empty }
        if let file = decode(data, as: type, includeInternal: includeInternal) {
            return file
        }
        return nil
    }

    private static func load<Snapshot: Codable & Equatable & Sendable>(
        from url: URL,
        as type: Snapshot.Type,
        includeInternal: Bool
    ) -> ItemArchiveFile<Snapshot> {
        loadForAppend(from: url, as: type, includeInternal: includeInternal) ?? .empty
    }

    private static func decode<Snapshot: Codable & Equatable & Sendable>(
        _ data: Data,
        as type: Snapshot.Type,
        includeInternal: Bool
    ) -> ItemArchiveFile<Snapshot>? {
        let decoder = JSONDecoder()
        if includeInternal {
            decoder.userInfo[BackupCodec.includeInternalKeys] = true
        }
        return try? decoder.decode(ItemArchiveFile<Snapshot>.self, from: data)
    }

    private static func encode<Snapshot: Codable & Equatable & Sendable>(
        _ file: ItemArchiveFile<Snapshot>,
        includeInternal: Bool
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if includeInternal {
            encoder.userInfo[BackupCodec.includeInternalKeys] = true
        }
        var payload = file
        payload.v = version
        return try encoder.encode(payload)
    }
}
