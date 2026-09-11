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
        let t = String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36)
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
    static func snapshot(from items: [Item], customs: [CustomDepartment] = []) -> [Staple] {
        items.compactMap { item in
            let name = item.name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return Staple(name: name, dept: DepartmentCatalog.resolved(item.dept, customs: customs))
        }
    }
}

/// Dringlichkeit eines Einkaufs-Artikels. Fehlender / unbekannter Key = `normal`.
enum ItemUrgency: String, Equatable, Codable, CaseIterable, Sendable {
    case urgent
    case normal
    case later

    static func parse(_ raw: String?) -> ItemUrgency {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ItemUrgency.urgent.rawValue: return .urgent
        case ItemUrgency.later.rawValue: return .later
        default: return .normal
        }
    }

    var next: ItemUrgency {
        switch self {
        case .urgent: return .normal
        case .normal: return .later
        case .later: return .urgent
        }
    }

    /// Chip-Icon: eilig ⚡, normal ↔ (U+2194), später ↓ (U+2193).
    /// `normal` ist das eine Zeichen ↔ — nicht leer, nicht `<->`, nicht ○/–.
    var symbol: String {
        switch self {
        case .urgent: return "⚡"
        case .normal: return "\u{2194}"
        case .later: return "\u{2193}"
        }
    }

    var label: String {
        switch self {
        case .urgent: return "eilig"
        case .normal: return "normal"
        case .later: return "später"
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
    /// Nur Inbox-Abruf und expliziter Fremd-Datei-Import. Fehlender Key = false.
    var imported: Bool
    /// Fehlender / unbekannter Key = `normal`.
    var urgency: ItemUrgency

    enum CodingKeys: String, CodingKey {
        case id, name, dept, done, added, ord, doneChangedAt, imported, urgency
    }

    init(
        id: String,
        name: String,
        dept: String,
        done: Bool,
        added: Double,
        ord: Double,
        doneChangedAt: Double? = nil,
        imported: Bool = false,
        urgency: ItemUrgency = .normal
    ) {
        self.id = id
        self.name = name
        self.dept = dept
        self.done = done
        self.added = added
        self.ord = ord
        self.doneChangedAt = doneChangedAt
        self.imported = imported
        self.urgency = urgency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Item.makeID()
        let rawDept = try c.decodeIfPresent(String.self, forKey: .dept) ?? Department.sonstiges.rawValue
        let trimmedDept = rawDept.trimmingCharacters(in: .whitespacesAndNewlines)
        dept = trimmedDept.isEmpty ? Department.sonstiges.rawValue : trimmedDept
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        added = try Self.decodeNumber(c, key: .added) ?? Date.nowEpochMillis
        ord = try Self.decodeNumber(c, key: .ord) ?? added
        doneChangedAt = try Self.decodeNumber(c, key: .doneChangedAt)
        imported = try c.decodeIfPresent(Bool.self, forKey: .imported) ?? false
        urgency = ItemUrgency.parse(try c.decodeIfPresent(String.self, forKey: .urgency))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(dept, forKey: .dept)
        try c.encode(done, forKey: .done)
        try c.encode(added, forKey: .added)
        try c.encode(ord, forKey: .ord)
        try c.encode(imported, forKey: .imported)
        try c.encode(urgency.rawValue, forKey: .urgency)
        if encoder.userInfo[BackupCodec.includeInternalKeys] as? Bool == true, let doneChangedAt {
            try c.encode(doneChangedAt, forKey: .doneChangedAt)
        }
    }

    var sortOrd: Double { ord.isFinite ? ord : added }

    static func makeID() -> String {
        let t = String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36)
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
    /// Eigene Abteilungen (`{ id, title }`). Alte Stände ohne Feld → `[]`.
    var customDepartments: [CustomDepartment]
    /// Intern: Strukturänderungen (Import, Hinzufügen, Ladenwechsel).
    var listRevision: UInt64

    enum CodingKeys: String, CodingKey {
        case currentStoreId, stores, items, mappings, walkMode, staples, savedLists, customDepartments, listRevision
    }

    init(currentStoreId: String, stores: [Store], items: [Item], mappings: [String: String], walkMode: Bool, staples: [Staple], listRevision: UInt64, savedLists: [SavedList] = [], customDepartments: [CustomDepartment] = []) {
        self.currentStoreId = currentStoreId
        self.stores = stores
        self.items = items
        self.mappings = mappings
        self.walkMode = walkMode
        self.staples = staples
        self.savedLists = savedLists
        self.customDepartments = customDepartments
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
        customDepartments = try c.decodeIfPresent([CustomDepartment].self, forKey: .customDepartments) ?? []
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
            savedLists: [],
            customDepartments: []
        )
    }

    func departmentTitle(_ id: String) -> String {
        DepartmentCatalog.title(for: id, customs: customDepartments)
    }

    func resolveDept(_ id: String) -> String {
        DepartmentCatalog.resolved(id, customs: customDepartments)
    }

    var pickerDepartmentIds: [String] {
        DepartmentCatalog.knownIds(customs: customDepartments)
    }

    var currentStore: Store {
        stores.first(where: { $0.id == currentStoreId }) ?? stores.first ?? Store.seeds[0]
    }

    var openCount: Int { items.filter { !$0.done }.count }
    var doneCount: Int { items.filter(\.done).count }
    /// Kompakter Fortschritt: offen/erledigt/gesamt, inkl. vor/nach. Leer: `0/0/0`.
    var progressLabel: String { "\(openCount)/\(doneCount)/\(items.count)" }
    /// Eine Zeile für die Watch-Nav: Laden links, dann Einkauf oo/xx/yy. Lange Namen
    /// kürzen, damit der Zähler auf 41mm nicht vom Systemtitel abgeschnitten wird.
    var watchTitle: String {
        "\(Self.clippedWatchStoreName(currentStore.name))  Einkauf \(progressLabel)"
    }

    var complicationSnapshot: ComplicationSnapshot { .make(from: self) }

    /// Zeichenbudget vor „Einkauf oo/xx/yy“, passend für die 41mm-Leiste
    /// (Edeka/Aldi/Rewe/Lidl/dm ungekürzt, längere Namen mit Auslassung).
    static let watchStoreNameLimit = 6

    static func clippedWatchStoreName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > watchStoreNameLimit else { return trimmed }
        return String(trimmed.prefix(watchStoreNameLimit - 1)) + "…"
    }

    func grouped() -> [DeptGroup] {
        ListGrouping.groups(items: items, store: currentStore, customs: customDepartments)
    }
}

/// Anzeige für die Watch-Complication. `progressLabel` bleibt `oo/xx/yy` (wie `watchTitle`);
/// der sichtbare Zähler ist `compactCountText` (nur offene Anzahl, bei 0 „erledigt“).
/// Titel fest **Einkauf** (nicht Ladenname, nicht „Einkaufsliste“ — zu lang für Corner/Inline).
struct ComplicationSnapshot: Equatable, Sendable {
    static let widgetKind = "EinkaufProgress"
    static let openURL = URL(string: "einkauf://list")!
    /// Rectangular / Corner / Inline — kürzer als „Einkaufsliste“.
    static let titleLabel = "Einkauf"

    var progressLabel: String
    /// Immer `titleLabel`. Feldname bleibt `storeName` für die bestehenden Widget-Bindings.
    var storeName: String
    var isEmpty: Bool
    /// Gauge 0…1 (erledigt/gesamt); leere Liste ist 0.
    var progress: Double = 0

    static let placeholder = ComplicationSnapshot(
        progressLabel: "5/2/7",
        storeName: titleLabel,
        isEmpty: false,
        progress: 2.0 / 7.0
    )

    static func make(from state: AppState) -> ComplicationSnapshot {
        let total = state.items.count
        return ComplicationSnapshot(
            progressLabel: state.progressLabel,
            storeName: titleLabel,
            isEmpty: state.items.isEmpty,
            progress: total == 0 ? 0 : Double(state.doneCount) / Double(total)
        )
    }

    /// Rohteile von `progressLabel` (`oo` / `xx` / `yy`) — nicht auf Complications anzeigen.
    private var progressParts: [String] {
        progressLabel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    var openText: String { progressParts.indices.contains(0) ? progressParts[0] : progressLabel }
    var doneText: String { progressParts.indices.contains(1) ? progressParts[1] : "" }
    var totalText: String { progressParts.indices.contains(2) ? progressParts[2] : "" }
    var openCount: Int { Int(openText) ?? 0 }

    /// Sichtbarer Complication-Zähler: `"\(openCount)"`, bei 0 das Wort „erledigt“.
    var compactCountText: String {
        openCount == 0 ? "erledigt" : openText
    }

    /// Inline: fester Titel **Einkauf** und kompakter Zähler (0 → „erledigt“).
    var inlineText: String {
        let name = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return compactCountText }
        return "\(name)  \(compactCountText)"
    }

    var accessibilityLabel: String {
        let title = storeName.isEmpty ? Self.titleLabel : storeName
        if openCount == 0 {
            return "\(title), Liste erledigt"
        }
        return "\(title), \(openCount) offen"
    }
}

/// Zähler `oo/xx/yy` (offen / erledigt / gesamt) für eine Homescreen-Widget-Zeile.
struct HomeWidgetCounts: Equatable, Sendable {
    var open: Int
    var done: Int
    var total: Int

    var progressLabel: String { "\(open)/\(done)/\(total)" }
    var isEmpty: Bool { total == 0 }

    static func shopping(_ state: AppState) -> HomeWidgetCounts {
        HomeWidgetCounts(open: state.openCount, done: state.doneCount, total: state.items.count)
    }

    static func todo(_ tasks: [TodoTask]) -> HomeWidgetCounts {
        let done = tasks.filter(\.completed).count
        return HomeWidgetCounts(open: tasks.count - done, done: done, total: tasks.count)
    }
}

/// Homescreen-Widget (iPhone): Einkauf + To-Do der **aktuellen Liste**, beide `oo/xx/yy`.
struct HomeWidgetSnapshot: Equatable, Sendable {
    static let widgetKind = "EinkaufHome"
    static let openURL = URL(string: "einkauf://list")!
    static let todoURL = URL(string: "einkauf://todo")!
    static let einkaufLabel = "Einkaufsliste"
    static let einkaufLabelCompact = "Einkauf"
    /// Spaltenköpfe der Mini-Tabelle (mittel/groß).
    static let columnHeaders = ("Offen", "Erledigt", "Gesamt")

    var einkauf: HomeWidgetCounts
    var todo: HomeWidgetCounts
    /// Listenname für `To Do (…)` — **Alle** bei leerer oder unbekannter ID.
    var todoListName: String

    static let placeholder = HomeWidgetSnapshot(
        einkauf: HomeWidgetCounts(open: 5, done: 2, total: 7),
        todo: HomeWidgetCounts(open: 3, done: 1, total: 4),
        todoListName: "Haus"
    )

    static func make(
        from state: AppState,
        todo todoState: TodoState = .empty,
        currentListId: String = ""
    ) -> HomeWidgetSnapshot {
        let listId = TodoListFilter.resolved(currentListId)
        let tasks = TodoListFilter.tasks(todoState.tasks, currentListId: listId)
        return HomeWidgetSnapshot(
            einkauf: .shopping(state),
            todo: .todo(tasks),
            todoListName: TodoListFilter.title(lists: todoState.lists, currentListId: listId)
        )
    }

    /// Einkauf-Zähler, gleiche Form wie `AppState.progressLabel`.
    var progressLabel: String { einkauf.progressLabel }

    var todoProgressLabel: String { todo.progressLabel }

    var todoRowLabel: String { "To Do (\(todoListName))" }

    func compactEinkaufLine(short: Bool) -> String {
        let name = short ? Self.einkaufLabelCompact : Self.einkaufLabel
        return "\(name): \(einkauf.progressLabel)"
    }

    var compactTodoLine: String {
        "\(todoRowLabel): \(todo.progressLabel)"
    }

    var accessibilityLabel: String {
        "\(Self.einkaufLabel) \(spoken(einkauf)), \(todoRowLabel) \(spoken(todo))"
    }

    private func spoken(_ counts: HomeWidgetCounts) -> String {
        if counts.isEmpty { return "Liste leer" }
        return "\(counts.open) offen, \(counts.done) erledigt, \(counts.total) gesamt"
    }
}

struct DeptGroup: Identifiable, Equatable, Sendable {
    /// SwiftUI-Identität inkl. Laden, damit Abschnitte bei Ladenwechsel als neu gelten.
    var id: String
    var storeId: String
    /// Abteilungs-ID (`obst`, `kuehlung`, …) — nicht `id` verwenden, das enthält den Laden.
    var dept: String
    var items: [Item]
    var title: String

    init(storeId: String, dept: String, items: [Item], customs: [CustomDepartment] = []) {
        self.id = "\(storeId)|\(dept)"
        self.storeId = storeId
        self.dept = dept
        self.items = items
        self.title = DepartmentCatalog.title(for: dept, customs: customs)
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

    var itemId: String? {
        if case .item(_, let item) = self { return item.id }
        return nil
    }

    var isItem: Bool {
        if case .item = self { return true }
        return false
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
    static func groups(items: [Item], store: Store, customs: [CustomDepartment] = []) -> [DeptGroup] {
        let layout = StoreLayout.sanitized(store.layout, customs: customs)
        let inLayout = Set(layout)

        var byDept: [String: [Item]] = [:]
        for item in items {
            let dept = DepartmentCatalog.resolved(item.dept, customs: customs)
            byDept[dept, default: []].append(item)
        }
        for key in byDept.keys {
            byDept[key]?.sort(by: sortItems)
        }

        var groups: [DeptGroup] = []
        var used = Set<String>()
        func push(_ dept: String) {
            guard !used.contains(dept), let arr = byDept[dept], !arr.isEmpty else { return }
            groups.append(DeptGroup(storeId: store.id, dept: dept, items: arr, customs: customs))
            used.insert(dept)
        }

        for dept in layout where dept != Department.nach.rawValue {
            push(dept)
        }
        for dept in DepartmentCatalog.knownIds(customs: customs) where !inLayout.contains(dept) {
            push(dept)
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

    /// Gleiche Abteilungsreihenfolge wie `groups`. Bei `hidingCompleted` nur offene Artikel;
    /// Abteilungen ohne offene Artikel fallen weg. Artikel bleiben in der Liste.
    static func visibleGroups(_ groups: [DeptGroup], hidingCompleted: Bool) -> [DeptGroup] {
        guard hidingCompleted else { return groups }
        return groups.compactMap { group in
            let open = group.items.filter { !$0.done }
            guard !open.isEmpty else { return nil }
            var next = group
            next.items = open
            return next
        }
    }

    /// Fortschritt der übergebenen Gruppen: offen/erledigt/gesamt (`oo/xx/yy`).
    static func progressLabel(groups: [DeptGroup]) -> String {
        let items = groups.flatMap(\.items)
        let done = items.filter(\.done).count
        return "\(items.count - done)/\(done)/\(items.count)"
    }

    /// `id` enthält Laden und Listenposition, nicht nur die Abteilungs-ID.
    /// `hidingCompleted` filtert nur die Anzeige (Geh-Liste / PDF); Artikel bleiben in der Liste.
    static func walkListRows(groups: [DeptGroup], storeId: String, hidingCompleted: Bool = false) -> [WalkListRow] {
        let visible = visibleGroups(groups, hidingCompleted: hidingCompleted)
        return walkLines(groups: visible, storeId: storeId).enumerated().map { index, line in
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
