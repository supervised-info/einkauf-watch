import Foundation

extension Notification.Name {
    /// Nach einem To-Do-Write, analog `.einkaufStateDidChangeOnDisk`.
    static let todoStateDidChangeOnDisk = Notification.Name("todo.stateDidChangeOnDisk")
}

/// Eigene Datei `todo-local.json` im selben App-Group-Ordner `Einkauf/` wie die Einkaufsliste.
/// Schreibt nur diese To-Do-Datei und benutzt **nicht** `BackupCodec`.
enum TodoPersistence {
    private static let fileName = "todo-local.json"
    private static let folderName = "Einkauf"

    static var fileURL: URL {
        appGroupFileURL ?? applicationSupportURL
    }

    private static var applicationSupportURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    private static var appGroupFileURL: URL? {
        guard let container = Persistence.appGroupContainerURL else { return nil }
        let folder = container.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static func load() -> TodoState? {
        if let state = read(fileURL) {
            return state
        }
        #if os(iOS) || os(watchOS)
        if fileURL != applicationSupportURL, let state = read(applicationSupportURL) {
            save(state)
            return state
        }
        #endif
        return nil
    }

    static func save(_ state: TodoState) {
        do {
            try write(state)
        } catch {
            // Persistenzfehler sollen die UI nicht crashen.
        }
    }

    static func write(_ state: TodoState) throws {
        let data = try TodoCodec.encodeLocal(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func read(_ url: URL) -> TodoState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? TodoCodec.decodeLocal(data)
    }
}
