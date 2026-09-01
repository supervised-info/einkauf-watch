import Foundation

enum Persistence {
    private static let fileName = "einkauf-local.json"

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Einkauf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static func load() -> AppState? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? BackupCodec.decodeLocal(data)
    }

    static func save(_ state: AppState) {
        do {
            let data = try BackupCodec.encodeLocal(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistenzfehler sollen die UI nicht crashen.
        }
    }
}
