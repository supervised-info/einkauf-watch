import Foundation

/// HTML-To-Do Markdown (`todo-liste.md`): offene Personengruppen, dann `## Abgeschlossen`.
enum TodoMarkdown {
    static let unlabeledPerson = "(Keine Person)"

    static func encode(
        _ state: TodoState,
        exportedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> Data {
        let normalized = TodoCodec.normalized(state)
        guard !normalized.tasks.isEmpty else { throw TodoCodecError.nothingToExport }
        let ts = TodoTime.exportedAtLabel(exportedAt, timeZone: timeZone)
        var md = "# To-Do Liste\nExportiert am: \(ts)\n"
        let open = normalized.tasks.filter { !$0.completed }
        let done = normalized.tasks.filter(\.completed)

        for (person, group) in TodoHTMLGrouping.groupByPerson(open) {
            md += "\n## \(person.isEmpty ? unlabeledPerson : person)\n\n"
            for task in group {
                md += line(task, checkbox: " ")
                md += metaComment(task, lists: normalized.lists)
            }
        }

        if !done.isEmpty {
            md += "\n---\n\n## Abgeschlossen\n"
            for (person, group) in TodoHTMLGrouping.groupByPerson(done) {
                md += "\n### \(person.isEmpty ? unlabeledPerson : person)\n\n"
                for task in group {
                    md += line(task, checkbox: "x")
                    md += metaComment(task, lists: normalized.lists)
                }
            }
        }
        return Data(md.utf8)
    }

    static func decode(_ data: Data) throws -> TodoState {
        let stripped = IncomingJSON.stripBOM(data)
        guard let text = String(data: stripped, encoding: .utf8)
                ?? String(data: stripped, encoding: .isoLatin1) else {
            throw TodoCodecError.invalidText
        }
        return try decode(text)
    }

    static func decode(_ text: String) throws -> TodoState {
        if TodoImport.looksLikeEinkaufMarkdown(text) {
            throw TodoCodecError.einkaufFile
        }
        var result: [TodoTask] = []
        var importedLists: [TodoNamedList] = []
        var person = ""
        var lastIndex: Int?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let last = lastIndex, applyNewMeta(trimmed, to: &result[last], lists: &importedLists) { continue }
            if let last = lastIndex, applyOldMeta(trimmed, to: &result[last], lists: &importedLists) { continue }
            if let sec2 = heading(trimmed, level: 2) {
                person = sec2 == "Abgeschlossen" ? "" : (sec2 == unlabeledPerson ? "" : sec2)
                continue
            }
            if let sec3 = heading(trimmed, level: 3) {
                person = sec3 == unlabeledPerson ? "" : sec3
                continue
            }
            if var task = parseCheckboxLine(trimmed) {
                task.person = person
                result.append(task)
                lastIndex = result.count - 1
            }
        }
        return try TodoCodec.makeImportedState(tasks: result, lists: importedLists)
    }

    private static func line(_ task: TodoTask, checkbox: String) -> String {
        let prio = task.prioA.isEmpty ? "" : "[\(task.prioA)\(task.prioB)] "
        let due = task.dueDate.isEmpty ? "" : " (\(task.dueDate))"
        let compl = checkbox == "x" && !task.completedDate.isEmpty ? " {\(task.completedDate)}" : ""
        return "- [\(checkbox)] \(prio)\(task.text)\(due)\(compl)\n"
    }

    private static func metaComment(_ task: TodoTask, lists: [TodoNamedList] = []) -> String {
        var parts = [
            "#\(task.uid)",
            task.changedBy.isEmpty ? "–" : task.changedBy,
            "erstellt \(task.createdAt.isEmpty ? "–" : TodoTime.formatDateTimeUTC(task.createdAt))",
            "geändert \(task.updatedAt.isEmpty ? "–" : TodoTime.formatDateTimeUTC(task.updatedAt))"
        ]
        if let from = task.reopenedFromUid {
            parts.append("von #\(from) am \(TodoTime.displayDay(task.reopenedAt))")
        }
        if let to = task.reopenedToUid {
            parts.append("→ #\(to) am \(TodoTime.displayDay(task.reopenedAt))")
        }
        if let listId = TodoJSON.normalizedListId(task.listId) {
            if let name = lists.first(where: { $0.id == listId })?.name, !name.isEmpty {
                parts.append("Liste \(name)")
            }
            parts.append("list:\(listId)")
        }
        return "  <!-- \(parts.joined(separator: " | ")) -->\n"
    }

    private static func heading(_ line: String, level: Int) -> String? {
        let marks = String(repeating: "#", count: level)
        guard line.hasPrefix(marks + " "), !line.hasPrefix(marks + "#") else { return nil }
        return String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)
    }

    /// HTML: `<!-- #4 | TS/NA | erstellt … | geändert … | von #x am … | → #y am … -->`
    private static func applyNewMeta(_ line: String, to task: inout TodoTask, lists: inout [TodoNamedList]) -> Bool {
        guard line.hasPrefix("<!--"), line.hasSuffix("-->") else { return false }
        let inner = String(line.dropFirst(4).dropLast(3)).trimmingCharacters(in: .whitespaces)
        guard inner.hasPrefix("#") else { return false }
        let parts = inner.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let uidPart = parts.first, uidPart.hasPrefix("#"),
              let uid = Int64(uidPart.dropFirst()), uid > 0 else { return false }
        task.uid = uid
        if parts.count > 1 {
            let changed = parts[1]
            task.changedBy = (changed == "–" || changed == "-") ? "" : changed
        }
        if parts.count > 2, parts[2].hasPrefix("erstellt ") {
            let value = String(parts[2].dropFirst("erstellt ".count))
            task.createdAt = value == "–" ? "" : TodoTime.parseDMYtoISO(value)
        }
        if parts.count > 3, parts[3].hasPrefix("geändert ") {
            let value = String(parts[3].dropFirst("geändert ".count))
            task.updatedAt = value == "–" ? "" : TodoTime.parseDMYtoISO(value)
        }
        var listName = ""
        for part in parts.dropFirst(4) {
            if let von = parseHashDate(part, prefix: "von #") {
                task.reopenedFromUid = von.uid
                if !von.day.isEmpty { task.reopenedAt = von.day }
            } else if let to = parseHashDate(part, prefix: "→ #") {
                task.reopenedToUid = to.uid
                if !to.day.isEmpty { task.reopenedAt = to.day }
            } else if part.hasPrefix("list:") {
                task.listId = TodoJSON.normalizedListId(String(part.dropFirst(5)))
            } else if part.hasPrefix("Liste ") {
                listName = String(part.dropFirst("Liste ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if task.listId == nil, !listName.isEmpty {
            if let existing = lists.first(where: { $0.name == listName }) {
                task.listId = existing.id
            } else {
                let id = TodoJSON.newListId()
                task.listId = id
                lists.append(TodoNamedList(id: id, name: listName))
            }
        } else {
            rememberList(id: task.listId, name: listName, lists: &lists)
        }
        return true
    }

    private static func parseHashDate(_ part: String, prefix: String) -> (uid: Int64, day: String)? {
        guard part.hasPrefix(prefix) else { return nil }
        let rest = String(part.dropFirst(prefix.count))
        guard let amRange = rest.range(of: " am ") else {
            if let uid = Int64(rest.trimmingCharacters(in: .whitespaces)), uid > 0 {
                return (uid, "")
            }
            return nil
        }
        let uidStr = rest[..<amRange.lowerBound].trimmingCharacters(in: .whitespaces)
        guard let uid = Int64(uidStr), uid > 0 else { return nil }
        let day = TodoTime.parseDMYDate(String(rest[amRange.upperBound...]))
        return (uid, day)
    }

    /// Alt: `<!-- todo: uid=N reopenedFrom=… -->`
    private static func applyOldMeta(_ line: String, to task: inout TodoTask, lists: inout [TodoNamedList]) -> Bool {
        guard line.hasPrefix("<!--"), line.hasSuffix("-->") else { return false }
        let inner = String(line.dropFirst(4).dropLast(3)).trimmingCharacters(in: .whitespaces)
        let lower = inner.lowercased()
        guard lower.hasPrefix("todo:") else { return false }
        let body = String(inner.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        var obj: [String: String] = [:]
        for token in body.split(whereSeparator: \.isWhitespace) {
            let pieces = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }
            obj[String(pieces[0])] = String(pieces[1])
        }
        if let uid = Int64(obj["uid"] ?? ""), uid > 0 { task.uid = uid }
        if let from = Int64(obj["reopenedFrom"] ?? ""), from > 0 { task.reopenedFromUid = from }
        if let to = Int64(obj["reopenedTo"] ?? ""), to > 0 { task.reopenedToUid = to }
        task.reopenedAt = TodoJSON.isoDate(obj["reopenedAt"])
        task.createdAt = TodoJSON.isoTimestamp(obj["createdAt"])
        task.updatedAt = TodoJSON.isoTimestamp(obj["updatedAt"])
        task.changedBy = obj["changedBy"] ?? ""
        task.listId = TodoJSON.normalizedListId(obj["listId"])
        rememberList(id: task.listId, name: obj["listName"] ?? "", lists: &lists)
        return true
    }

    private static func rememberList(id: String?, name: String, lists: inout [TodoNamedList]) {
        guard let id = TodoJSON.normalizedListId(id) else { return }
        if lists.contains(where: { $0.id == id }) { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        lists.append(TodoNamedList(id: id, name: trimmed.isEmpty ? id : trimmed))
    }

    /// HTML: `- [x] [A1]? text (due)? {done}?`
    private static func parseCheckboxLine(_ line: String) -> TodoTask? {
        guard line.hasPrefix("- ["), line.count >= 6 else { return nil }
        let mark = line[line.index(line.startIndex, offsetBy: 3)]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        guard line.dropFirst(4).hasPrefix("] ") else { return nil }
        var rest = String(line.dropFirst(6))
        var prioA = ""
        var prioB = ""
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let token = String(rest[rest.index(after: rest.startIndex)..<close])
            let isPrio: Bool = {
                guard let a = token.first, ("A"..."Z").contains(a) else { return false }
                if token.count == 1 { return true }
                if token.count == 2 {
                    return ("1"..."9").contains(token[token.index(after: token.startIndex)])
                }
                return false
            }()
            if isPrio {
                prioA = String(token.first!)
                if token.count == 2 {
                    prioB = String(token[token.index(after: token.startIndex)])
                }
                rest = String(rest[rest.index(after: close)...])
                if rest.hasPrefix(" ") { rest.removeFirst() }
            }
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        var completedDate = ""
        if rest.hasSuffix("}"), let brace = rest.lastIndex(of: "{") {
            let inner = String(rest[rest.index(after: brace)..<rest.index(before: rest.endIndex)])
            if TodoJSON.isoDate(inner) == inner, inner.count == 10 {
                completedDate = inner
                rest = String(rest[..<brace]).trimmingCharacters(in: .whitespaces)
            }
        }
        var dueDate = ""
        if rest.hasSuffix(")"), let open = rest.lastIndex(of: "(") {
            let inner = String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])
            if TodoJSON.isoDate(inner) == inner, inner.count == 10 {
                dueDate = inner
                rest = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
            }
        }
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return TodoTask(
            uid: 0,
            text: text,
            completed: mark != " ",
            prioA: prioA,
            prioB: prioB,
            dueDate: dueDate,
            completedDate: completedDate
        )
    }
}
