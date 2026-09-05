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

    /// Scope vor dem Lesen starten und über die Auswahl-Sheet-Lebensdauer halten.
    /// `stopAccess()` nach Schreiben (Übernehmen) oder beim Abbrechen / Dismiss.
    static func beginRetrieve() throws -> InboxRetrieveSession {
        let url = try resolvedURL()
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let items = try readItems(from: url)
            return InboxRetrieveSession(url: url, items: items, didStartAccess: scoped)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
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

    /// Abgewählte Zeilen zurückschreiben (eine pro Zeile, UTF-8). Leer = `Data()` wie bisher.
    static func rewrite(url: URL, remainingItems: [String]) throws {
        let data = Data(InboxParser.fileText(remainingItems: remainingItems).utf8)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw InboxBookmarkError.writeFailed
        }
    }

    /// v1: ganzen gelesenen Snapshot verbrauchen und Datei leer schreiben.
    /// Concurrent Append während des Abrufs ist kein v1-Ziel.
    static func rewriteEmpty(url: URL) throws {
        try rewrite(url: url, remainingItems: [])
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
            return "Inbox-Datei konnte nicht geschrieben werden."
        }
    }
}

/// Hält den Security-Scope von Lesen bis Übernehmen / Abbrechen.
/// `items` folgt der Sheet-Liste (Löschen schreibt sofort, ohne Import).
final class InboxRetrieveSession: Identifiable {
    let id = UUID()
    let url: URL
    var items: [String]
    private let didStartAccess: Bool
    private var stopped = false

    init(url: URL, items: [String], didStartAccess: Bool) {
        self.url = url
        self.items = items
        self.didStartAccess = didStartAccess
    }

    /// Datei auf die noch sichtbaren Zeilen kürzen; Scope bleibt fürs Sheet aktiv.
    func rewriteRemaining(_ remainingItems: [String]) throws {
        try InboxBookmarkStore.rewrite(url: url, remainingItems: remainingItems)
        items = remainingItems
    }

    func stopAccess() {
        guard !stopped else { return }
        stopped = true
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        stopAccess()
    }
}
