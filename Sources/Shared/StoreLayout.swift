import Foundation

/// Layout-Regeln wie in der PWA: `vor` immer zuerst, `nach` immer zuletzt.
enum StoreLayout {
    static func sanitized(_ layout: [String]) -> [String] {
        var seen = Set<String>()
        var middle: [String] = []
        for id in layout where Department.isKnown(id) && !seen.contains(id) {
            seen.insert(id)
            if isLocked(id) { continue }
            middle.append(id)
        }
        return [Department.vor.rawValue] + middle + [Department.nach.rawValue]
    }

    static func unused(in layout: [String]) -> [String] {
        let set = Set(sanitized(layout))
        return Department.allCases.map(\.rawValue).filter { !set.contains($0) }
    }

    static func isLocked(_ id: String) -> Bool {
        id == Department.vor.rawValue || id == Department.nach.rawValue
    }

    static func move(_ layout: [String], id: String, by: Int) -> [String] {
        var layout = sanitized(layout)
        guard !isLocked(id), let idx = layout.firstIndex(of: id) else { return layout }
        let j = idx + by
        guard layout.indices.contains(j), !isLocked(layout[j]) else { return layout }
        layout.swapAt(idx, j)
        return sanitized(layout)
    }

    /// SwiftUI-`onMove`: frei sortieren, `vor`/`nach` bleiben durch `sanitized` außen.
    static func moving(_ layout: [String], from source: IndexSet, to destination: Int) -> [String] {
        var layout = sanitized(layout)
        guard !source.isEmpty else { return layout }
        for idx in source {
            guard layout.indices.contains(idx), !isLocked(layout[idx]) else { return layout }
        }
        layout.move(fromOffsets: source, toOffset: destination)
        return sanitized(layout)
    }

    static func adding(_ id: String, to layout: [String]) -> [String] {
        guard Department.isKnown(id) else { return sanitized(layout) }
        var layout = sanitized(layout)
        if layout.contains(id) { return layout }
        if let nach = layout.firstIndex(of: Department.nach.rawValue) {
            layout.insert(id, at: nach)
        } else {
            layout.append(id)
        }
        return sanitized(layout)
    }

    static func removing(_ id: String, from layout: [String]) -> [String] {
        guard !isLocked(id) else { return sanitized(layout) }
        return sanitized(layout.filter { $0 != id })
    }

    static func reset(storeId: String, current: [String]) -> [String] {
        if let seed = Store.seeds.first(where: { $0.id == storeId }) {
            return sanitized(seed.layout)
        }
        return sanitized(StoreCatalog.customDefaultLayout)
    }
}

/// Anlegen/Löschen eigener Läden wie in der PWA (`createStore` / `deleteStore`).
enum StoreCatalog {
    static let nameMax = 60
    static let customDefaultLayout = ["vor", "sonstiges", "nach"]

    static func makeID() -> String {
        let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt64.random(in: 0..<0xFFFFFF), radix: 36)
        return "s\(t)\(r)"
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

    static func create(name raw: String, copying source: Store, id: String? = nil) -> Store? {
        guard let name = sanitizedName(raw) else { return nil }
        return Store(
            id: id ?? makeID(),
            name: name,
            layout: StoreLayout.sanitized(source.layout),
            builtin: false
        )
    }

    static func delete(
        id: String,
        stores: [Store],
        currentId: String
    ) -> (stores: [Store], currentId: String)? {
        guard let victim = stores.first(where: { $0.id == id }), !victim.builtin else { return nil }
        let remaining = stores.filter { $0.id != id }
        let merged = BackupCodec.mergeBuiltinSeeds(remaining)
        var nextCurrent = currentId
        if nextCurrent == id {
            nextCurrent = merged.first(where: { $0.id == "edeka" })?.id ?? merged.first?.id ?? "edeka"
        }
        return (merged, nextCurrent)
    }
}
