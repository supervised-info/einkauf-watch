import Foundation

/// Stamm auf die Einkaufsliste setzen — wie HTML `applyStaple` / `applyAllStaples`.
enum StapleApply {
    struct Outcome: Equatable {
        var items: [Item]
        var mappings: [String: String]
        var added: Int
        var reopened: Int
        var already: Int

        var didChange: Bool { added > 0 || reopened > 0 }
    }

    static func apply(
        _ staple: Staple,
        items: [Item],
        mappings: [String: String],
        nextOrd: Double,
        now: Double = Date.nowEpochMillis
    ) -> Outcome {
        let name = staple.name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return Outcome(items: items, mappings: mappings, added: 0, reopened: 0, already: 0)
        }
        var dept = staple.dept
        if !Department.isKnown(dept) {
            dept = DepartmentGuesser.guess(name, mappings: mappings)
        }
        let key = DepartmentGuesser.mappingKey(name)
        var items = items
        var mappings = mappings
        if let idx = items.firstIndex(where: { DepartmentGuesser.mappingKey($0.name) == key }) {
            if items[idx].done {
                items[idx].done = false
                items[idx].dept = dept
                items[idx].doneChangedAt = now
                mappings[key] = dept
                return Outcome(items: items, mappings: mappings, added: 0, reopened: 1, already: 0)
            }
            return Outcome(items: items, mappings: mappings, added: 0, reopened: 0, already: 1)
        }
        items.append(
            Item(
                id: Item.makeID(),
                name: name,
                dept: dept,
                done: false,
                added: now,
                ord: nextOrd,
                doneChangedAt: now
            )
        )
        mappings[key] = dept
        return Outcome(items: items, mappings: mappings, added: 1, reopened: 0, already: 0)
    }

    static func applyAll(
        _ staples: [Staple],
        items: [Item],
        mappings: [String: String],
        nextOrd: Double,
        now: Double = Date.nowEpochMillis
    ) -> Outcome {
        var items = items
        var mappings = mappings
        var ord = nextOrd
        var added = 0
        var reopened = 0
        var already = 0
        for staple in staples {
            let r = apply(staple, items: items, mappings: mappings, nextOrd: ord, now: now)
            items = r.items
            mappings = r.mappings
            added += r.added
            reopened += r.reopened
            already += r.already
            if r.added > 0 { ord += 1 }
        }
        return Outcome(items: items, mappings: mappings, added: added, reopened: reopened, already: already)
    }
}
