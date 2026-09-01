import Foundation

enum ItemEditing {
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

    /// Reorder nur innerhalb einer Abteilung (entspricht HTML-Drag in der Dept-Liste).
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
}
