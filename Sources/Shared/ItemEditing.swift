import Foundation

enum ItemEditing {
    /// Zeile in der iPhone-Bearbeiten-Liste: Abteilungsüberschrift oder Artikel.
    enum Row: Identifiable, Equatable {
        case header(String)
        case item(Item)

        var id: String {
            switch self {
            case .header(let dept): return "h:\(dept)"
            case .item(let item): return item.id
            }
        }

        var isHeader: Bool {
            if case .header = self { return true }
            return false
        }
    }

    /// Leerer Name: keine Änderung (wie HTML, Abbrechen/leeres Feld).
    static func rename(
        _ item: Item,
        to raw: String,
        mappings: [String: String]
    ) -> (Item, [String: String])? {
        let name = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var item = item
        let oldKey = DepartmentGuesser.mappingKey(item.name)
        item.name = name
        let newKey = DepartmentGuesser.mappingKey(item.name)
        if newKey != oldKey {
            item.dept = DepartmentGuesser.guess(name, mappings: mappings)
        }
        var mappings = mappings
        mappings[newKey] = item.dept
        return (item, mappings)
    }

    static func setDept(_ item: Item, dept: String, mappings: [String: String]) -> (Item, [String: String])? {
        guard Department.isKnown(dept) else { return nil }
        var item = item
        item.dept = dept
        var mappings = mappings
        mappings[DepartmentGuesser.mappingKey(item.name)] = dept
        return (item, mappings)
    }

    static func rows(from groups: [DeptGroup]) -> [Row] {
        var rows: [Row] = []
        for group in groups {
            rows.append(.header(group.id))
            for item in group.items {
                rows.append(.item(item))
            }
        }
        return rows
    }

    static func rows(items: [Item], store: Store) -> [Row] {
        rows(from: ListGrouping.groups(items: items, store: store))
    }

    static func itemIDs(in rows: [Row], at offsets: IndexSet) -> [String] {
        offsets.sorted().compactMap { idx in
            guard rows.indices.contains(idx), case .item(let item) = rows[idx] else { return nil }
            return item.id
        }
    }

    /// Reorder nur innerhalb einer Abteilung (ältere API, Tests).
    static func move(
        allItems: [Item],
        dept: String,
        from source: IndexSet,
        to destination: Int
    ) -> [Item] {
        var group = allItems.filter { Department.resolved($0.dept) == dept }
        group.sort(by: ListGrouping.sortItems)
        guard !source.isEmpty, source.allSatisfy({ group.indices.contains($0) }) else { return allItems }
        let dest = max(0, min(destination, group.count))
        group.move(fromOffsets: source, toOffset: dest)
        var byId = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        for (i, item) in group.enumerated() {
            var updated = item
            updated.ord = Double(i + 1)
            byId[item.id] = updated
        }
        return allItems.map { byId[$0.id]! }
    }

    /// SwiftUI-`onMove` auf der flachen Bearbeiten-Liste (Überschriften nicht mitziehen).
    /// Drop in eine andere Abteilung setzt `dept` + Mapping und `ord` an der Drop-Position.
    /// `vor`/`nach` sind gültige Ziele; die Gruppenreihenfolge kommt weiter vom Laden-Layout.
    static func moveRows(
        allItems: [Item],
        store: Store,
        from source: IndexSet,
        to destination: Int,
        mappings: [String: String]
    ) -> (items: [Item], mappings: [String: String])? {
        let rows = rows(items: allItems, store: store)
        let moving = source.sorted().compactMap { idx -> Item? in
            guard rows.indices.contains(idx), case .item(let item) = rows[idx] else { return nil }
            return item
        }
        guard !moving.isEmpty else { return nil }

        let remaining: [Row] = rows.enumerated().compactMap { idx, row in
            if source.contains(idx), case .item = row { return nil }
            return row
        }
        let dest = max(0, min(destination, remaining.count))
        guard let slot = dropSlot(remaining: remaining, destination: dest) else { return nil }
        guard Department.isKnown(slot.dept) else { return nil }

        if isNoOp(moving: moving, destDept: slot.dept, beforeId: slot.beforeId, allItems: allItems, store: store) {
            return nil
        }

        return applyDrop(
            allItems: allItems,
            moving: moving,
            destDept: slot.dept,
            beforeId: slot.beforeId,
            mappings: mappings,
            store: store
        )
    }

    /// Drop-Ziel nach Entfernen der Quelle, analog `Array.move` / SwiftUI `onMove`.
    /// Einfügen vor einer Überschrift = ans Ende der vorherigen Abteilung;
    /// Einfügen vor einem Artikel = diese Abteilung, vor diesem Artikel.
    static func dropSlot(remaining: [Row], destination: Int) -> (dept: String, beforeId: String?)? {
        guard !remaining.isEmpty else { return nil }
        let dest = max(0, min(destination, remaining.count))

        func header(before index: Int) -> String? {
            var i = index - 1
            while i >= 0 {
                if case .header(let dept) = remaining[i] { return dept }
                i -= 1
            }
            return nil
        }

        func firstItemID(afterHeaderAt headerIndex: Int) -> String? {
            var i = headerIndex + 1
            while i < remaining.count {
                switch remaining[i] {
                case .header: return nil
                case .item(let item): return item.id
                }
                i += 1
            }
            return nil
        }

        if dest == remaining.count {
            guard let dept = header(before: dest) else { return nil }
            return (dept, nil)
        }

        switch remaining[dest] {
        case .header(let dept):
            if let prev = header(before: dest) {
                return (prev, nil)
            }
            return (dept, firstItemID(afterHeaderAt: dest))
        case .item(let item):
            let dept = header(before: dest) ?? Department.resolved(item.dept)
            return (dept, item.id)
        }
    }

    private static func isNoOp(
        moving: [Item],
        destDept: String,
        beforeId: String?,
        allItems: [Item],
        store: Store
    ) -> Bool {
        guard moving.count == 1, let item = moving.first else { return false }
        guard Department.resolved(item.dept) == destDept else { return false }
        let group = ListGrouping.groups(items: allItems, store: store).first { $0.id == destDept }
        guard let ids = group?.items.map(\.id), let idx = ids.firstIndex(of: item.id) else { return false }
        if let beforeId {
            if beforeId == item.id { return true }
            return ids.indices.contains(idx + 1) && ids[idx + 1] == beforeId
        }
        return idx == ids.count - 1
    }

    private static func applyDrop(
        allItems: [Item],
        moving: [Item],
        destDept: String,
        beforeId: String?,
        mappings: [String: String],
        store: Store
    ) -> (items: [Item], mappings: [String: String]) {
        var mappings = mappings
        let movingIDs = Set(moving.map(\.id))
        let placed = moving.map { item -> Item in
            var item = item
            if Department.resolved(item.dept) != destDept {
                item.dept = destDept
                mappings[DepartmentGuesser.mappingKey(item.name)] = destDept
            } else {
                item.dept = destDept
            }
            return item
        }

        var byId = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        for item in placed {
            byId[item.id] = item
        }

        let othersDest = allItems
            .filter { !movingIDs.contains($0.id) && Department.resolved($0.dept) == destDept }
            .sorted(by: ListGrouping.sortItems)

        var destList: [Item] = []
        var didPlace = false
        if let beforeId {
            for item in othersDest {
                if !didPlace && item.id == beforeId {
                    destList.append(contentsOf: placed)
                    didPlace = true
                }
                destList.append(item)
            }
            if !didPlace {
                destList.append(contentsOf: placed)
            }
        } else {
            destList = othersDest + placed
        }

        for (i, item) in destList.enumerated() {
            var updated = item
            updated.ord = Double(i + 1)
            byId[item.id] = updated
        }

        var result = allItems.map { byId[$0.id]! }
        let groups = ListGrouping.groups(items: result, store: store)
        var n = 0.0
        for group in groups {
            for item in group.items {
                n += 1
                byId[item.id]?.ord = n
            }
        }
        result = allItems.map { byId[$0.id]! }
        return (result, mappings)
    }
}
