import Foundation

enum BackupError: Error, LocalizedError, Equatable {
    case notABackup
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notABackup: return "Keine gültige Einkauf-Backup-Datei."
        case .invalidJSON: return "Die Datei ist kein gültiges JSON."
        }
    }
}

enum BackupCodec {
    static let includeInternalKeys = CodingUserInfoKey(rawValue: "einkauf.includeInternal")!

    static func decode(_ data: Data) throws -> AppState {
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BackupError.invalidJSON
        }
        guard let dict = obj as? [String: Any] else { throw BackupError.notABackup }
        guard looksLikeBackup(dict) else { throw BackupError.notABackup }

        let currentStoreId = string(dict["currentStoreId"]) ?? "edeka"
        let stores = mergeBuiltinSeeds(sanitizeStores(dict["stores"]))
        let items = sanitizeItems(dict["items"])
        let mappings = sanitizeMappings(dict["mappings"])
        let walkMode = dict["walkMode"] as? Bool ?? false
        let staples: [Staple]
        if dict["staples"] == nil {
            staples = []
        } else {
            staples = sanitizeStaples(dict["staples"], mappings: mappings)
        }
        let listRevision = uint64(dict["listRevision"]) ?? 0
        let savedLists: [SavedList]
        if dict["savedLists"] == nil {
            savedLists = []
        } else {
            savedLists = sanitizeSavedLists(dict["savedLists"], mappings: mappings)
        }

        var current = currentStoreId
        if !stores.contains(where: { $0.id == current }) {
            current = stores.first?.id ?? "edeka"
        }

        return AppState(
            currentStoreId: current,
            stores: stores,
            items: items,
            mappings: mappings,
            walkMode: walkMode,
            staples: staples,
            listRevision: listRevision,
            savedLists: savedLists
        )
    }

    static func encodeExport(_ state: AppState) throws -> Data {
        let payload: [String: Any] = [
            "kind": "einkauf-backup",
            "v": 1,
            "currentStoreId": state.currentStoreId,
            "stores": state.stores.map { store in
                [
                    "id": store.id,
                    "name": store.name,
                    "layout": store.layout,
                    "builtin": store.builtin
                ] as [String: Any]
            },
            "mappings": state.mappings,
            "items": state.items.map { item in
                [
                    "id": item.id,
                    "name": item.name,
                    "dept": item.dept,
                    "done": item.done,
                    "added": item.added,
                    "ord": item.sortOrd
                ] as [String: Any]
            },
            "walkMode": state.walkMode,
            "layoutTrip": 1,
            "staples": state.staples.map { ["name": $0.name, "dept": $0.dept] },
            "savedLists": state.savedLists.map { list in
                [
                    "id": list.id,
                    "name": list.name,
                    "items": list.items.map { ["name": $0.name, "dept": $0.dept] }
                ] as [String: Any]
            }
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    static func encodeLocal(_ state: AppState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.userInfo[includeInternalKeys] = true
        return try encoder.encode(LocalEnvelope(kind: "einkauf-local", v: 1, state: state))
    }

    static func decodeLocal(_ data: Data) throws -> AppState {
        if let envelope = try? JSONDecoder().decode(LocalEnvelope.self, from: data) {
            return normalized(envelope.state)
        }
        return try decode(data)
    }

    static func looksLikeBackup(_ dict: [String: Any]) -> Bool {
        if string(dict["kind"]) == "einkauf-backup" { return true }
        let v = dict["v"] as? Int ?? (dict["v"] as? Double).map { Int($0) } ?? 0
        return v == 1 && dict["items"] is [Any] && dict["stores"] is [Any]
    }

    static func normalized(_ state: AppState) -> AppState {
        var next = state
        next.stores = mergeBuiltinSeeds(sanitizeStoreModels(state.stores))
        next.items = state.items.enumerated().map { idx, item in
            var it = item
            it.dept = Department.resolved(it.dept)
            if !it.ord.isFinite { it.ord = Double(idx + 1) }
            return it
        }
        if !next.stores.contains(where: { $0.id == next.currentStoreId }) {
            next.currentStoreId = next.stores.first?.id ?? "edeka"
        }
        var maps: [String: String] = [:]
        for (k, v) in state.mappings where Department.isKnown(v) {
            maps[k] = v
        }
        next.mappings = maps
        next.savedLists = sanitizeSavedListModels(state.savedLists, mappings: maps)
        return next
    }

    // MARK: - Sanitize

    static func sanitizeStores(_ raw: Any?) -> [Store] {
        guard let arr = raw as? [Any] else { return [] }
        return arr.compactMap { entry in
            guard let s = entry as? [String: Any] else { return nil }
            guard let id = string(s["id"]), let name = string(s["name"]), !id.isEmpty, !name.isEmpty else { return nil }
            return Store(id: id, name: name, layout: sanitizeLayout(s["layout"]), builtin: s["builtin"] as? Bool ?? false)
        }
    }

    static func sanitizeStoreModels(_ stores: [Store]) -> [Store] {
        stores.compactMap { s in
            guard !s.id.isEmpty, !s.name.isEmpty else { return nil }
            return Store(id: s.id, name: s.name, layout: sanitizeLayout(s.layout), builtin: s.builtin)
        }
    }

    static func sanitizeLayout(_ raw: Any?) -> [String] {
        let ids: [String]
        if let arr = raw as? [String] {
            ids = arr
        } else if let arr = raw as? [Any] {
            ids = arr.compactMap { string($0) }
        } else {
            ids = []
        }
        return sanitizeLayout(ids)
    }

    static func sanitizeLayout(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in ids where Department.isKnown(id) && !seen.contains(id) {
            seen.insert(id)
            out.append(id)
        }
        if out.isEmpty { out = ["sonstiges"] }
        if !out.contains("vor") { out.insert("vor", at: 0) }
        if !out.contains("nach") { out.append("nach") }
        return out
    }

    static func sanitizeItems(_ raw: Any?) -> [Item] {
        guard let arr = raw as? [Any] else { return [] }
        var items: [Item] = []
        for entry in arr {
            guard let s = entry as? [String: Any], let name = string(s["name"]) else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let added = number(s["added"]) ?? Date.nowEpochMillis
            let ord = number(s["ord"])
            items.append(
                Item(
                    id: string(s["id"]) ?? Item.makeID(),
                    name: trimmed,
                    dept: Department.resolved(string(s["dept"]) ?? ""),
                    done: s["done"] as? Bool ?? false,
                    added: added,
                    ord: ord ?? added,
                    doneChangedAt: number(s["doneChangedAt"])
                )
            )
        }
        for i in items.indices where !items[i].ord.isFinite {
            items[i].ord = Double(i + 1)
        }
        return items
    }

    static func sanitizeMappings(_ raw: Any?) -> [String: String] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in dict {
            if let dept = v as? String, Department.isKnown(dept) {
                out[k] = dept
            }
        }
        return out
    }

    static func sanitizeStaples(_ raw: Any?, mappings: [String: String]) -> [Staple] {
        guard let arr = raw as? [Any] else { return [] }
        var seen = Set<String>()
        var out: [Staple] = []
        for entry in arr {
            let name: String?
            var dept = ""
            if let s = entry as? String {
                name = s
            } else if let obj = entry as? [String: Any] {
                name = string(obj["name"])
                dept = string(obj["dept"]) ?? ""
            } else {
                name = nil
            }
            guard var n = name else { continue }
            n = n.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { continue }
            let key = DepartmentGuesser.mappingKey(n)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            if !Department.isKnown(dept) {
                dept = DepartmentGuesser.guess(n, mappings: mappings)
            }
            out.append(Staple(name: n, dept: dept))
        }
        return out
    }

    static func sanitizeSavedLists(_ raw: Any?, mappings: [String: String]) -> [SavedList] {
        guard let arr = raw as? [Any] else { return [] }
        return sanitizeSavedListModels(
            arr.compactMap { entry in
                guard let obj = entry as? [String: Any] else { return nil }
                let name = string(obj["name"]) ?? ""
                let id = string(obj["id"]) ?? ""
                let items = sanitizeSavedListItems(obj["items"], mappings: mappings)
                return SavedList(id: id, name: name, items: items)
            },
            mappings: mappings
        )
    }

    static func sanitizeSavedListModels(_ lists: [SavedList], mappings: [String: String]) -> [SavedList] {
        var seenIds = Set<String>()
        var out: [SavedList] = []
        for list in lists {
            guard let name = SavedList.sanitizedName(list.name) else { continue }
            let items = sanitizeSavedListItems(list.items, mappings: mappings)
            guard !items.isEmpty else { continue }
            var id = list.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || seenIds.contains(id) {
                id = SavedList.makeID()
            }
            seenIds.insert(id)
            out.append(SavedList(id: id, name: name, items: items))
        }
        return out
    }

    static func sanitizeSavedListItems(_ raw: Any?, mappings: [String: String]) -> [Staple] {
        guard let arr = raw as? [Any] else { return [] }
        var out: [Staple] = []
        for entry in arr {
            let name: String?
            var dept = ""
            if let s = entry as? String {
                name = s
            } else if let obj = entry as? [String: Any] {
                name = string(obj["name"])
                dept = string(obj["dept"]) ?? ""
            } else {
                name = nil
            }
            guard var n = name else { continue }
            n = n.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { continue }
            if !Department.isKnown(dept) {
                dept = DepartmentGuesser.guess(n, mappings: mappings)
            }
            out.append(Staple(name: n, dept: dept))
        }
        return out
    }

    static func sanitizeSavedListItems(_ items: [Staple], mappings: [String: String]) -> [Staple] {
        items.compactMap { staple in
            let n = staple.name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty else { return nil }
            var dept = staple.dept
            if !Department.isKnown(dept) {
                dept = DepartmentGuesser.guess(n, mappings: mappings)
            }
            return Staple(name: n, dept: dept)
        }
    }

    static func mergeBuiltinSeeds(_ stores: [Store]) -> [Store] {
        var byId = Dictionary(uniqueKeysWithValues: stores.map { ($0.id, $0) })
        for seed in Store.seeds {
            if var found = byId[seed.id] {
                found.builtin = true
                byId[seed.id] = found
            } else {
                byId[seed.id] = seed
            }
        }
        var out: [Store] = []
        for seed in Store.seeds {
            if let s = byId[seed.id] {
                out.append(s)
                byId.removeValue(forKey: seed.id)
            }
        }
        for store in stores {
            if byId[store.id] != nil {
                out.append(store)
                byId.removeValue(forKey: store.id)
            }
        }
        return out.isEmpty ? Store.seeds : out
    }

    private static func string(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return nil
    }

    private static func uint64(_ any: Any?) -> UInt64? {
        if let u = any as? UInt64 { return u }
        if let i = any as? Int, i >= 0 { return UInt64(i) }
        if let d = any as? Double, d >= 0 { return UInt64(d) }
        if let n = any as? NSNumber { return n.uint64Value }
        return nil
    }
}

private struct LocalEnvelope: Codable {
    var kind: String
    var v: Int
    var state: AppState
}
