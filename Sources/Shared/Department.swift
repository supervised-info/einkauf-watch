import Foundation

/// Abteilungen wie in der PWA (`DEPTS`). IDs der Builtins nicht ändern.
enum Department: String, CaseIterable, Codable, Identifiable, Sendable {
    case vor
    case obst
    case brot
    case bedienung
    case kuehlung
    case tiefkuehl
    case trocken
    case suess
    case getraenke
    case drogerie
    case sonstiges
    case nach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vor: return "Vor dem Einkauf"
        case .obst: return "Obst & Gemüse"
        case .brot: return "Brot & Backwaren"
        case .bedienung: return "Fleisch, Wurst, Käse"
        case .kuehlung: return "Kühlregal"
        case .tiefkuehl: return "Tiefkühl"
        case .trocken: return "Trockenwaren"
        case .suess: return "Süßwaren & Snacks"
        case .getraenke: return "Getränke"
        case .drogerie: return "Drogerie & Haushalt"
        case .sonstiges: return "Sonstiges"
        case .nach: return "Nach dem Einkauf"
        }
    }

    static func isKnown(_ id: String) -> Bool {
        Department(rawValue: id) != nil
    }

    /// Nur Builtins. Unbekannt → `sonstiges`. Eigene IDs: `DepartmentCatalog.resolved(_:customs:)`.
    static func resolved(_ id: String) -> String {
        DepartmentCatalog.resolved(id, customs: [])
    }

    static func title(for id: String) -> String {
        DepartmentCatalog.title(for: id, customs: [])
    }
}

/// Nutzer-Abteilung: stabile `id`, sichtbarer `title`. Builtins bleiben im Enum.
struct CustomDepartment: Identifiable, Equatable, Codable, Sendable {
    static let titleMax = 60

    var id: String
    var title: String

    static func makeID() -> String {
        let t = String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt64.random(in: 0..<0xFFFFFF), radix: 36)
        return "d\(t)\(r)"
    }

    static func sanitizedTitle(_ raw: String) -> String? {
        var title = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if title.count > titleMax {
            title = String(title.prefix(titleMax))
        }
        return title
    }
}

/// Builtin-Enum plus `customDepartments`. Eigene IDs überleben `resolved`, Unbekanntes → `sonstiges`.
enum DepartmentCatalog {
    static let builtinIds: [String] = Department.allCases.map(\.rawValue)

    static func knownIds(customs: [CustomDepartment]) -> [String] {
        builtinIds + customs.map(\.id)
    }

    static func isKnown(_ id: String, customs: [CustomDepartment] = []) -> Bool {
        Department.isKnown(id) || customs.contains(where: { $0.id == id })
    }

    static func title(for id: String, customs: [CustomDepartment] = []) -> String {
        if let builtin = Department(rawValue: id) { return builtin.title }
        if let custom = customs.first(where: { $0.id == id }) { return custom.title }
        return id
    }

    static func resolved(_ id: String, customs: [CustomDepartment] = []) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Department.sonstiges.rawValue }
        return isKnown(trimmed, customs: customs) ? trimmed : Department.sonstiges.rawValue
    }

    static func create(title raw: String, existing: [CustomDepartment], id: String? = nil) -> CustomDepartment? {
        guard let title = CustomDepartment.sanitizedTitle(raw) else { return nil }
        var newId = (id ?? CustomDepartment.makeID()).trimmingCharacters(in: .whitespacesAndNewlines)
        if newId.isEmpty || Department.isKnown(newId) || existing.contains(where: { $0.id == newId }) {
            newId = CustomDepartment.makeID()
            while Department.isKnown(newId) || existing.contains(where: { $0.id == newId }) {
                newId = CustomDepartment.makeID()
            }
        }
        return CustomDepartment(id: newId, title: title)
    }

    static func rename(id: String, title raw: String, in customs: [CustomDepartment]) -> [CustomDepartment]? {
        guard let idx = customs.firstIndex(where: { $0.id == id }) else { return nil }
        guard let title = CustomDepartment.sanitizedTitle(raw) else { return nil }
        var next = customs
        next[idx].title = title
        return next
    }

    /// Items, Stamm, gespeicherte Listen und Mappings mit `id` → `sonstiges`; ID aus allen Ladenwegen.
    static func remappingDeletion(
        _ id: String,
        items: [Item],
        staples: [Staple],
        savedLists: [SavedList],
        mappings: [String: String],
        stores: [Store],
        remainingCustoms: [CustomDepartment]
    ) -> (
        items: [Item],
        staples: [Staple],
        savedLists: [SavedList],
        mappings: [String: String],
        stores: [Store]
    ) {
        let fallback = Department.sonstiges.rawValue
        func remap(_ dept: String) -> String {
            dept == id ? fallback : dept
        }
        let items = items.map { item -> Item in
            var item = item
            item.dept = remap(item.dept)
            return item
        }
        let staples = staples.map { Staple(name: $0.name, dept: remap($0.dept)) }
        let savedLists = savedLists.map { list -> SavedList in
            var list = list
            list.items = list.items.map { Staple(name: $0.name, dept: remap($0.dept)) }
            return list
        }
        var mappings = mappings
        for (key, dept) in mappings where dept == id {
            mappings[key] = fallback
        }
        let stores = stores.map { store -> Store in
            var store = store
            store.layout = StoreLayout.sanitized(store.layout.filter { $0 != id }, customs: remainingCustoms)
            return store
        }
        return (items, staples, savedLists, mappings, stores)
    }
}
