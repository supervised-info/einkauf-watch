import Foundation

enum Persistence {
    private static let fileName = "einkauf-local.json"
    /// App Group für iPhone-App, iPhone-Widget, Watch-App und Watch-Complication (nicht iCloud).
    static let appGroupId = "group.net.tschelle.einkauf"

    static var fileURL: URL {
        appGroupFileURL ?? applicationSupportURL
    }

    private static var applicationSupportURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Einkauf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    /// iOS + watchOS: App und Widget lesen dieselbe `einkauf-local.json`.
    private static var appGroupFileURL: URL? {
        #if os(iOS) || os(watchOS)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return nil
        }
        let folder = container.appendingPathComponent("Einkauf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
        #else
        return nil
        #endif
    }

    static func load() -> AppState? {
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

    static func save(_ state: AppState) {
        do {
            let data = try BackupCodec.encodeLocal(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistenzfehler sollen die UI nicht crashen.
        }
    }

    private static func read(_ url: URL) -> AppState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? BackupCodec.decodeLocal(data)
    }
}
