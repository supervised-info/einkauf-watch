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
        return sanitized(current)
    }
}
