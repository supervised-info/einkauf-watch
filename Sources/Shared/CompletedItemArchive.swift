import Foundation

/// Snapshot eines endgültig gelöschten **erledigten** Eintrags.
/// Ein Eintrag = ein Item; Bulk-Deletes schreiben mehrere Einträge (Burst-`archivedAt` ok).
struct ItemArchiveEntry<Snapshot: Codable>: Codable, Equatable, Sendable where Snapshot: Equatable & Sendable {
    var archivedAt: String
    var item: Snapshot
}

/// Zeile in der Einstellungen-Archivliste (neueste zuerst).
/// `fileIndex` ist der Index in `entries` (Datei-Reihenfolge, älteste zuerst).
struct ArchiveDisplayRow: Equatable, Identifiable, Sendable {
    var fileIndex: Int
    var title: String
    var archivedAt: String

    var id: Int { fileIndex }
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

    /// Entfernt **einen** Eintrag am Datei-Index (`entries`-Reihenfolge). Kein Clear-All.
    @discardableResult
    static func deleteEinkauf(at index: Int) -> Bool {
        deleteEinkauf(at: IndexSet(integer: index))
    }

    /// Entfernt ausgewählte Einträge am Datei-Index. Kein Clear-All.
    @discardableResult
    static func deleteEinkauf(at indices: IndexSet) -> Bool {
        delete(at: indices, from: einkaufFileURL, as: Item.self, includeInternal: true)
    }

    /// Entfernt **einen** Eintrag am Datei-Index (`entries`-Reihenfolge). Kein Clear-All.
    @discardableResult
    static func deleteTodo(at index: Int) -> Bool {
        deleteTodo(at: IndexSet(integer: index))
    }

    /// Entfernt ausgewählte Einträge am Datei-Index. Kein Clear-All.
    @discardableResult
    static func deleteTodo(at indices: IndexSet) -> Bool {
        delete(at: indices, from: todoFileURL, as: TodoTask.self, includeInternal: false)
    }

    /// Angezeigte Liste (neueste zuerst) → Datei-Indizes für `delete*`.
    static func fileIndices(fromDisplayed offsets: IndexSet, entryCount: Int) -> IndexSet {
        guard entryCount > 0 else { return [] }
        return IndexSet(offsets.compactMap { displayed in
            let fileIndex = entryCount - 1 - displayed
            return (0..<entryCount).contains(fileIndex) ? fileIndex : nil
        })
    }

    /// Neueste zuerst; `fileIndex` entspricht `entries` in der Datei.
    static func displayRows<Snapshot>(
        _ entries: [ItemArchiveEntry<Snapshot>],
        title: (Snapshot) -> String
    ) -> [ArchiveDisplayRow] {
        guard !entries.isEmpty else { return [] }
        return stride(from: entries.count - 1, through: 0, by: -1).map { index in
            let entry = entries[index]
            return ArchiveDisplayRow(
                fileIndex: index,
                title: displayTitle(title(entry.item)),
                archivedAt: displayArchivedAt(entry.archivedAt)
            )
        }
    }

    static func displayTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Ohne Titel" : trimmed
    }

    /// Lesbares `archivedAt` (`dd.MM.yyyy, HH:mm`, lokal). Unparsbar → Original.
    static func displayArchivedAt(_ iso: String, timeZone: TimeZone = .current) -> String {
        let raw = iso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let date = TodoTime.parseIsoTimestamp(raw) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter.string(from: date)
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
        file.entries.append(contentsOf: snapshots.map { ItemArchiveEntry(archivedAt: stamp, item: $0) })
        _ = save(file, to: url, includeInternal: includeInternal)
    }

    /// Einzel-Löschen am Datei-Index. Ungültige Indizes / kaputtes JSON: Datei unangetastet.
    @discardableResult
    private static func delete<Snapshot: Codable & Equatable & Sendable>(
        at indices: IndexSet,
        from url: URL,
        as type: Snapshot.Type,
        includeInternal: Bool
    ) -> Bool {
        guard !indices.isEmpty else { return false }
        guard var file = loadForAppend(from: url, as: type, includeInternal: includeInternal) else {
            return false
        }
        let valid = IndexSet(indices.filter { file.entries.indices.contains($0) })
        guard !valid.isEmpty else { return false }
        file.entries.remove(atOffsets: valid)
        return save(file, to: url, includeInternal: includeInternal)
    }

    @discardableResult
    private static func save<Snapshot: Codable & Equatable & Sendable>(
        _ file: ItemArchiveFile<Snapshot>,
        to url: URL,
        includeInternal: Bool
    ) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var payload = file
            payload.v = version
            try encode(payload, includeInternal: includeInternal).write(to: url, options: [.atomic])
            return true
        } catch {
            // Archivfehler sollen Löschen nicht crashen.
            return false
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
