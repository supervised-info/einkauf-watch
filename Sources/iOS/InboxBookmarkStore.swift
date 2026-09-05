import Foundation

/// Security-scoped Bookmark auf die vom Nutzer gewählte `inbox.txt` (Dateien-Picker).
/// Persistenz im App-Sandbox-`UserDefaults` — kein Extra-Container, keine Shared DB.
enum InboxBookmarkStore {
    static let bookmarkKey = "einkauf.inbox.bookmark"
    static let nameKey = "einkauf.inbox.displayName"

    static var displayName: String? {
        let name = defaults.string(forKey: nameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static var hasBookmark: Bool {
        bookmarkData != nil
    }

    static func connect(url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: nameKey)
    }

    /// Bookmark auflösen, Security-Scope halten, `body` ausführen, Scope beenden.
    /// Stale Bookmarks werden einmal neu gespeichert; schlägt das fehl, Verbindung löschen.
    static func withResolvedURL<T>(_ body: (URL) throws -> T) throws -> T {
        let url = try resolvedURL()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    static func readItems(from url: URL) throws -> [String] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw InboxBookmarkError.unreadable
        }
        return InboxParser.items(from: data)
    }

    /// v1: ganzen gelesenen Snapshot verbrauchen und Datei leer schreiben.
    /// Concurrent Append während des Abrufs ist kein v1-Ziel.
    static func rewriteEmpty(url: URL) throws {
        do {
            try Data().write(to: url, options: .atomic)
        } catch {
            throw InboxBookmarkError.writeFailed
        }
    }

    static func clear() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: nameKey)
    }

    private static var defaults: UserDefaults { .standard }

    private static var bookmarkData: Data? {
        defaults.data(forKey: bookmarkKey)
    }

    private static func resolvedURL() throws -> URL {
        guard let data = bookmarkData else {
            throw InboxBookmarkError.notConnected
        }
        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            clear()
            throw InboxBookmarkError.stale
        }
        if stale {
            do {
                try connect(url: url)
            } catch {
                clear()
                throw InboxBookmarkError.stale
            }
        }
        return url
    }
}

enum InboxBookmarkError: LocalizedError, Equatable {
    case notConnected
    case stale
    case unreadable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Zuerst Inbox verbinden…"
        case .stale:
            return "Inbox-Verbindung ungültig. Bitte erneut verbinden."
        case .unreadable:
            return "Inbox-Datei konnte nicht gelesen werden."
        case .writeFailed:
            return "Inbox-Datei konnte nicht geleert werden."
        }
    }
}
