import Foundation

/// HTML-To-Do CSV: UTF-8-BOM, Semikolon, quoted; offene Zeilen, dann `## Abgeschlossen`.
enum TodoCSV {
    static let header = [
        "Person", "Prio A", "Prio B", "Aufgabe", "Enddatum", "Abgeschlossen am",
        "UID", "Reopened From UID", "Reopened To UID", "Reopened At",
        "Erstellt am", "Geändert am", "Geändert von"
    ]

    static let listNameHeader = "Liste"
    static let listIdHeader = "List-ID"

    static func encode(_ state: TodoState) throws -> Data {
        let normalized = TodoCodec.normalized(state)
        guard !normalized.tasks.isEmpty else { throw TodoCodecError.nothingToExport }
        let includeLists = !normalized.lists.isEmpty
            || normalized.tasks.contains { TodoJSON.normalizedListId($0.listId) != nil }
        let cols = includeLists ? header + [listNameHeader, listIdHeader] : header
        let open = normalized.tasks.filter { !$0.completed }
        let done = normalized.tasks.filter(\.completed)
        var rows: [[String]] = [cols]
        for (person, group) in TodoHTMLGrouping.groupByPerson(open) {
            for task in group {
                rows.append(row(task, person: person, includeCompletedDate: false, lists: normalized.lists, includeLists: includeLists))
            }
        }
        if !done.isEmpty {
            rows.append(["## Abgeschlossen"] + Array(repeating: "", count: cols.count - 1))
            for (person, group) in TodoHTMLGrouping.groupByPerson(done) {
                for task in group {
                    rows.append(row(task, person: person, includeCompletedDate: true, lists: normalized.lists, includeLists: includeLists))
                }
            }
        }
        let csv = rows.map { cols in
            cols.map(quote).joined(separator: ";")
        }.joined(separator: "\r\n")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        return data
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
        let lines = text.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { throw TodoCodecError.empty }
        let headerPlain = first.replacingOccurrences(of: "\"", with: "").lowercased()
        if headerPlain.contains("abteilung") || headerPlain.contains("einkauf") {
            throw TodoCodecError.einkaufFile
        }
        let sep: Character = first.contains(";") ? ";" : ","
        let headerCols = splitCSVLine(first, separator: sep).map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
        }
        let listNameIdx = columnIndex(headerCols, names: [listNameHeader, "Liste"])
        let listIdIdx = columnIndex(headerCols, names: [listIdHeader, "ListId", "listId"])
        var result: [TodoTask] = []
        var importedLists: [TodoNamedList] = []
        for line in lines.dropFirst() {
            let cols = splitCSVLine(line, separator: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            let person = col(cols, 0)
            let text = col(cols, 3)
            if text.isEmpty || person.hasPrefix("##") { continue }
            let completedDateRaw = col(cols, 5)
            let completedDate = isIsoDate(completedDateRaw) ? completedDateRaw : ""
            let dueRaw = col(cols, 4)
            let reopenedAtRaw = col(cols, 9)
            let createdRaw = col(cols, 10)
            let updatedRaw = col(cols, 11)
            var listId = listIdIdx.map { TodoJSON.normalizedListId(col(cols, $0)) } ?? nil
            let listName = listNameIdx.map { col(cols, $0).trimmingCharacters(in: .whitespaces) } ?? ""
            if listId == nil, !listName.isEmpty {
                if let existing = importedLists.first(where: { $0.name == listName }) {
                    listId = existing.id
                } else {
                    listId = TodoJSON.newListId()
                    importedLists.append(TodoNamedList(id: listId!, name: listName))
                }
            } else if let listId {
                if !importedLists.contains(where: { $0.id == listId }) {
                    importedLists.append(TodoNamedList(id: listId, name: listName.isEmpty ? listId : listName))
                }
            }
            result.append(
                TodoTask(
                    uid: Int64(col(cols, 6)) ?? 0,
                    text: text,
                    completed: isIsoDate(completedDateRaw),
                    prioA: TodoJSON.prioA(col(cols, 1)),
                    prioB: TodoJSON.prioB(col(cols, 2)),
                    dueDate: isIsoDate(dueRaw) ? dueRaw : "",
                    completedDate: completedDate,
                    person: person,
                    reopenedFromUid: Int64(col(cols, 7)).flatMap { $0 > 0 ? $0 : nil },
                    reopenedToUid: Int64(col(cols, 8)).flatMap { $0 > 0 ? $0 : nil },
                    reopenedAt: isIsoDate(reopenedAtRaw) ? reopenedAtRaw : "",
                    createdAt: isoOrDMY(createdRaw),
                    updatedAt: isoOrDMY(updatedRaw),
                    changedBy: col(cols, 12),
                    listId: listId
                )
            )
        }
        return try TodoCodec.makeImportedState(tasks: result, lists: importedLists)
    }

    private static func row(
        _ task: TodoTask,
        person: String,
        includeCompletedDate: Bool,
        lists: [TodoNamedList] = [],
        includeLists: Bool = false
    ) -> [String] {
        var cols = [
            person,
            task.prioA,
            task.prioB,
            task.text,
            task.dueDate,
            includeCompletedDate ? task.completedDate : "",
            task.uid == 0 ? "" : String(task.uid),
            task.reopenedFromUid.map(String.init) ?? "",
            task.reopenedToUid.map(String.init) ?? "",
            task.reopenedAt,
            TodoTime.formatDateTimeUTC(task.createdAt),
            TodoTime.formatDateTimeUTC(task.updatedAt),
            task.changedBy
        ]
        if includeLists {
            let id = TodoJSON.normalizedListId(task.listId)
            cols.append(id.flatMap { lid in lists.first { $0.id == lid }?.name } ?? "")
            cols.append(id ?? "")
        }
        return cols
    }

    private static func columnIndex(_ header: [String], names: [String]) -> Int? {
        let lower = header.map { $0.lowercased() }
        for name in names {
            if let i = lower.firstIndex(of: name.lowercased()) { return i }
        }
        return nil
    }

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func col(_ cols: [String], _ i: Int) -> String {
        i < cols.count ? cols[i] : ""
    }

    private static func isIsoDate(_ value: String) -> Bool {
        TodoJSON.isoDate(value) == value && value.count == 10
    }

    private static func isoOrDMY(_ value: String) -> String {
        if value.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil {
            return value
        }
        return TodoTime.parseDMYtoISO(value)
    }

    static func splitCSVLine(_ line: String, separator: Character) -> [String] {
        var cols: [String] = []
        var cur = ""
        var inQ = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if inQ {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" {
                        cur.append("\"")
                        i = next
                    } else {
                        inQ = false
                    }
                } else {
                    cur.append(ch)
                }
            } else if ch == "\"" {
                inQ = true
            } else if ch == separator {
                cols.append(cur)
                cur = ""
            } else {
                cur.append(ch)
            }
            i = line.index(after: i)
        }
        cols.append(cur)
        return cols
    }
}
