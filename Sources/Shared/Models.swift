import Foundation

struct Store: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var name: String
    var layout: [String]
    var builtin: Bool

    static let seeds: [Store] = [
        Store(id: "edeka", name: "Edeka", layout: ["vor", "obst", "bedienung", "brot", "kuehlung", "tiefkuehl", "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach"], builtin: true),
        Store(id: "aldi", name: "Aldi", layout: ["vor", "obst", "brot", "kuehlung", "tiefkuehl", "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach"], builtin: true),
        Store(id: "rewe", name: "Rewe", layout: ["vor", "obst", "brot", "bedienung", "trocken", "suess", "kuehlung", "tiefkuehl", "getraenke", "drogerie", "sonstiges", "nach"], builtin: true),
        Store(id: "lidl", name: "Lidl", layout: ["vor", "obst", "brot", "kuehlung", "tiefkuehl", "trocken", "suess", "getraenke", "drogerie", "sonstiges", "nach"], builtin: true),
        Store(id: "dm", name: "dm", layout: ["vor", "drogerie", "trocken", "getraenke", "sonstiges", "nach"], builtin: true),
        Store(id: "eigenes", name: "Eigenes Layout", layout: ["vor", "sonstiges", "nach"], builtin: true)
    ]
}

struct Staple: Equatable, Codable, Sendable {
    var name: String
    var dept: String
}

/// Benannte Anlass-Liste (Grillen, Drogerie). Snapshot nur `name` + `dept`, ohne Häkchen.
struct SavedList: Identifiable, Equatable, Codable, Sendable {
    static let nameMax = 60

    var id: String
    var name: String
    var items: [Staple]

    static func makeID() -> String {
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt64.random(in: 0..<0xFFFFFF), radix: 36)
        return "l\(t)\(r)"
    }

    static func sanitizedName(_ raw: String) -> String? {
        var name = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if name.count > nameMax {
            name = String(name.prefix(nameMax))
        }
        return name
    }

    /// Aktuelle Artikel inkl. erledigter — nur Name und Abteilung, damit Apply wieder öffnet.
    static func snapshot(from items: [Item]) -> [Staple] {
        items.compactMap { item in
            let name = item.name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return Staple(name: name, dept: Department.resolved(item.dept))
        }
    }
}

struct Item: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var name: String
    var dept: String
    var done: Bool
    var added: Double
    var ord: Double
    /// Nur intern (Sync). Wird beim PWA-Export weggelassen.
    var doneChangedAt: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, dept, done, added, ord, doneChangedAt
    }

    init(id: String, name: String, dept: String, done: Bool, added: Double, ord: Double, doneChangedAt: Double? = nil) {
        self.id = id
        self.name = name
        self.dept = dept
        self.done = done
        self.added = added
        self.ord = ord
        self.doneChangedAt = doneChangedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Item.makeID()
        let rawDept = try c.decodeIfPresent(String.self, forKey: .dept) ?? Department.sonstiges.rawValue
        dept = Department.resolved(rawDept)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        added = try Self.decodeNumber(c, key: .added) ?? Date.nowEpochMillis
        ord = try Self.decodeNumber(c, key: .ord) ?? added
        doneChangedAt = try Self.decodeNumber(c, key: .doneChangedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(dept, forKey: .dept)
        try c.encode(done, forKey: .done)
        try c.encode(added, forKey: .added)
        try c.encode(ord, forKey: .ord)
        if encoder.userInfo[BackupCodec.includeInternalKeys] as? Bool == true, let doneChangedAt {
            try c.encode(doneChangedAt, forKey: .doneChangedAt)
        }
    }

    var sortOrd: Double { ord.isFinite ? ord : added }

    static func makeID() -> String {
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt64.random(in: 0..<0xFFFFFF), radix: 36)
        return "i\(t)\(r)"
    }

    private static func decodeNumber(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double? {
        guard c.contains(key) else { return nil }
        if let v = try? c.decode(Double.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return Double(v) }
        if let v = try? c.decode(String.self, forKey: key), let d = Double(v) { return d }
        return nil
    }
}

struct AppState: Equatable, Codable, Sendable {
    var currentStoreId: String
    var stores: [Store]
    var items: [Item]
    var mappings: [String: String]
    var walkMode: Bool
    var staples: [Staple]
    var savedLists: [SavedList]
    /// Intern: Strukturänderungen (Import, Hinzufügen, Ladenwechsel).
    var listRevision: UInt64

    enum CodingKeys: String, CodingKey {
        case currentStoreId, stores, items, mappings, walkMode, staples, savedLists, listRevision
    }

    init(currentStoreId: String, stores: [Store], items: [Item], mappings: [String: String], walkMode: Bool, staples: [Staple], listRevision: UInt64, savedLists: [SavedList] = []) {
        self.currentStoreId = currentStoreId
        self.stores = stores
        self.items = items
        self.mappings = mappings
        self.walkMode = walkMode
        self.staples = staples
        self.savedLists = savedLists
        self.listRevision = listRevision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentStoreId = try c.decodeIfPresent(String.self, forKey: .currentStoreId) ?? "edeka"
        stores = try c.decodeIfPresent([Store].self, forKey: .stores) ?? Store.seeds
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        mappings = try c.decodeIfPresent([String: String].self, forKey: .mappings) ?? [:]
        walkMode = try c.decodeIfPresent(Bool.self, forKey: .walkMode) ?? false
        staples = try c.decodeIfPresent([Staple].self, forKey: .staples) ?? []
        savedLists = try c.decodeIfPresent([SavedList].self, forKey: .savedLists) ?? []
        listRevision = try c.decodeIfPresent(UInt64.self, forKey: .listRevision) ?? 0
    }

    static var seed: AppState {
        AppState(
            currentStoreId: "edeka",
            stores: Store.seeds,
            items: [],
            mappings: [:],
            walkMode: false,
            staples: [],
            listRevision: 0,
            savedLists: []
        )
    }

    var currentStore: Store {
        stores.first(where: { $0.id == currentStoreId }) ?? stores.first ?? Store.seeds[0]
    }

    var openCount: Int { items.filter { !$0.done }.count }
    var doneCount: Int { items.filter(\.done).count }
    /// Kompakter Fortschritt für die Watch-Leiste: erledigt/gesamt, inkl. vor/nach.
    var progressLabel: String { "\(doneCount)/\(items.count)" }
    /// Eine Zeile für die Watch-Nav: Laden links, dann Einkauf xx/yy. Lange Namen
    /// kürzen, damit der Zähler auf 41mm nicht vom Systemtitel abgeschnitten wird.
    var watchTitle: String {
        "\(Self.clippedWatchStoreName(currentStore.name))  Einkauf \(progressLabel)"
    }

    var complicationSnapshot: ComplicationSnapshot { .make(from: self) }

    /// Zeichenbudget vor „Einkauf xx/yy“, passend für die 41mm-Leiste
    /// (Edeka/Aldi/Rewe/Lidl/dm ungekürzt, längere Namen mit Auslassung).
    static let watchStoreNameLimit = 6

    static func clippedWatchStoreName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > watchStoreNameLimit else { return trimmed }
        return String(trimmed.prefix(watchStoreNameLimit - 1)) + "…"
    }

    func grouped() -> [DeptGroup] {
        ListGrouping.groups(items: items, store: currentStore)
    }
}

/// Anzeige für die Watch-Complication: gleicher Zähler wie `watchTitle` (`doneCount/items.count`).
struct ComplicationSnapshot: Equatable, Sendable {
    static let widgetKind = "EinkaufProgress"
    static let openURL = URL(string: "einkauf://list")!

    var progressLabel: String
    var storeName: String
    var isEmpty: Bool
    /// Gauge 0…1; leere Liste ist 0.
    var progress: Double = 0

    static let placeholder = ComplicationSnapshot(
        progressLabel: "2/7",
        storeName: "Edeka",
        isEmpty: false,
        progress: 2.0 / 7.0
    )

    static func make(from state: AppState) -> ComplicationSnapshot {
        let total = state.items.count
        return ComplicationSnapshot(
            progressLabel: state.progressLabel,
            storeName: AppState.clippedWatchStoreName(state.currentStore.name),
            isEmpty: state.items.isEmpty,
            progress: total == 0 ? 0 : Double(state.doneCount) / Double(total)
        )
    }

    /// Zähler-Teile für das gestapelte Circular-Label (`xx` über `yy`).
    var doneText: String {
        if let slash = progressLabel.firstIndex(of: "/") {
            return String(progressLabel[..<slash])
        }
        return progressLabel
    }

    var totalText: String {
        if let slash = progressLabel.firstIndex(of: "/") {
            return String(progressLabel[progressLabel.index(after: slash)...])
        }
        return ""
    }

    /// Inline: kurzer Ladenname und `xx/yy` (leere Liste bleibt `0/0`).
    var inlineText: String {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return progressLabel }
        return "\(name)  \(progressLabel)"
    }

    var accessibilityLabel: String {
        let store = storeName.isEmpty ? "Einkauf" : storeName
        if isEmpty {
            return "\(store), Liste leer"
        }
        return "\(store), \(progressLabel)"
    }
}

/// Homescreen-Widget (iPhone): gleicher Zähler wie `watchTitle` / `ComplicationSnapshot` (`doneCount/items.count`, inkl. vor/nach).
struct HomeWidgetSnapshot: Equatable, Sendable {
    static let widgetKind = "EinkaufHome"
    static let openURL = URL(string: "einkauf://list")!
    static let openItemLimit = 5

    var progressLabel: String
    var storeName: String
    var isEmpty: Bool
    var openItemNames: [String]

    static let placeholder = HomeWidgetSnapshot(
        progressLabel: "2/7",
        storeName: "Edeka",
        isEmpty: false,
        openItemNames: ["Milch", "Äpfel", "Klopapier"]
    )

    static func make(from state: AppState) -> HomeWidgetSnapshot {
        HomeWidgetSnapshot(
            progressLabel: state.progressLabel,
            storeName: state.currentStore.name,
            isEmpty: state.items.isEmpty,
            openItemNames: ListGrouping.openItemNames(
                items: state.items,
                store: state.currentStore,
                limit: openItemLimit
            )
        )
    }

    var accessibilityLabel: String {
        let store = storeName.isEmpty ? "Einkauf" : storeName
        if isEmpty {
            return "\(store), Liste leer"
        }
        if openItemNames.isEmpty {
            return "\(store), \(progressLabel)"
        }
        return "\(store), \(progressLabel), als nächstes " + openItemNames.joined(separator: ", ")
    }
}

struct DeptGroup: Identifiable, Equatable, Sendable {
    /// SwiftUI-Identität inkl. Laden, damit Abschnitte bei Ladenwechsel als neu gelten.
    var id: String
    var storeId: String
    /// Abteilungs-ID (`obst`, `kuehlung`, …) — nicht `id` verwenden, das enthält den Laden.
    var dept: String
    var items: [Item]
    var title: String { Department.title(for: dept) }

    init(storeId: String, dept: String, items: [Item]) {
        self.id = "\(storeId)|\(dept)"
        self.storeId = storeId
        self.dept = dept
        self.items = items
    }
}

/// Flache Geh-Modus-Zeile. Keine List-`Section` — SwiftUI behält sonst die Abteilungsreihenfolge.
enum WalkLine: Identifiable, Equatable, Sendable {
    case header(storeId: String, dept: String)
    case item(storeId: String, Item)

    var id: String {
        switch self {
        case .header(let storeId, let dept):
            return "\(storeId)|h:\(dept)"
        case .item(let storeId, let item):
            return "\(storeId)|i:\(item.id)"
        }
    }

    var headerDept: String? {
        if case .header(_, let dept) = self { return dept }
        return nil
    }
}

/// ForEach-Zeile inkl. Laden und Position, damit Views beim Ladenwechsel nicht wiederverwendet werden.
struct WalkListRow: Identifiable, Equatable, Sendable {
    var id: String
    var line: WalkLine
}

enum ListGrouping {
    /// `vor` zuerst, `nach` zuletzt; `sonstiges` bleibt an der Position im Ladenweg.
    /// Extra-Abteilungen mit Artikeln, die nicht im Layout stehen, danach (vor `nach`). `item.dept` bleibt unverändert.
    static func groups(items: [Item], store: Store) -> [DeptGroup] {
        let layout = StoreLayout.sanitized(store.layout)
        let inLayout = Set(layout)

        var byDept: [String: [Item]] = [:]
        for item in items {
            let dept = Department.resolved(item.dept)
            byDept[dept, default: []].append(item)
        }
        for key in byDept.keys {
            byDept[key]?.sort(by: sortItems)
        }

        var groups: [DeptGroup] = []
        var used = Set<String>()
        func push(_ dept: String) {
            guard !used.contains(dept), let arr = byDept[dept], !arr.isEmpty else { return }
            groups.append(DeptGroup(storeId: store.id, dept: dept, items: arr))
            used.insert(dept)
        }

        for dept in layout where dept != Department.nach.rawValue {
            push(dept)
        }
        for dept in Department.allCases where !inLayout.contains(dept.rawValue) {
            push(dept.rawValue)
        }
        push(Department.nach.rawValue)
        return groups
    }

    static func walkLines(groups: [DeptGroup], storeId: String) -> [WalkLine] {
        var lines: [WalkLine] = []
        for group in groups {
            lines.append(.header(storeId: storeId, dept: group.dept))
            for item in group.items {
                lines.append(.item(storeId: storeId, item))
            }
        }
        return lines
    }

    /// Offene Artikel in Geh-Modus-Reihenfolge (erledigte ausgelassen).
    static func openItemNames(items: [Item], store: Store, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var names: [String] = []
        for group in groups(items: items, store: store) {
            for item in group.items where !item.done {
                names.append(item.name)
                if names.count >= limit { return names }
            }
        }
        return names
    }

    /// `id` enthält Laden und Listenposition, nicht nur die Abteilungs-ID.
    static func walkListRows(groups: [DeptGroup], storeId: String) -> [WalkListRow] {
        walkLines(groups: groups, storeId: storeId).enumerated().map { index, line in
            WalkListRow(id: "\(storeId)|\(index)|\(line.id)", line: line)
        }
    }

    static func sortItems(_ a: Item, _ b: Item) -> Bool {
        if a.sortOrd != b.sortOrd { return a.sortOrd < b.sortOrd }
        if a.added != b.added { return a.added < b.added }
        return a.name.compare(b.name, locale: Locale(identifier: "de")) == .orderedAscending
    }
}

enum StateMerge {
    /// Listenstruktur folgt der höheren `listRevision`.
    /// Abhaken (`done`) wird je Artikel über `doneChangedAt` gemerged.
    static func merge(local: AppState, remote: AppState) -> AppState {
        let base: AppState
        let other: AppState
        if remote.listRevision > local.listRevision {
            base = remote
            other = local
        } else {
            base = local
            other = remote
        }

        let otherById = Dictionary(uniqueKeysWithValues: other.items.map { ($0.id, $0) })
        var items = base.items
        for i in items.indices {
            if let incoming = otherById[items[i].id] {
                items[i] = pickDone(base: items[i], other: incoming)
            }
        }
        var result = base
        result.items = items
        result.listRevision = max(local.listRevision, remote.listRevision)
        return result
    }

    static func pickDone(base: Item, other: Item) -> Item {
        var item = base
        let a = base.doneChangedAt ?? 0
        let b = other.doneChangedAt ?? 0
        if b > a {
            item.done = other.done
            item.doneChangedAt = other.doneChangedAt
        } else if b == a && a == 0 && other.done != base.done {
            // Ohne Zeitstempel: „erledigt“ gewinnt, damit ein Abhaken nicht verloren geht.
            item.done = base.done || other.done
        }
        return item
    }
}

extension Date {
    static var nowEpochMillis: Double { Date().timeIntervalSince1970 * 1000 }
}
