import Foundation

/// HTML-To-Do CSV: UTF-8-BOM, Semikolon, quoted; offene Zeilen, dann `## Abgeschlossen`.
enum TodoCSV {
    static let header = [
        "Person", "Prio A", "Prio B", "Aufgabe", "Enddatum", "Abgeschlossen am",
        "UID", "Reopened From UID", "Reopened To UID", "Reopened At",
        "Erstellt am", "Geändert am", "Geändert von"
    ]

    static func encode(_ state: TodoState) throws -> Data {
        let normalized = TodoCodec.normalized(state)
        guard !normalized.tasks.isEmpty else { throw TodoCodecError.nothingToExport }
        let open = normalized.tasks.filter { !$0.completed }
        let done = normalized.tasks.filter(\.completed)
        var rows: [[String]] = [header]
        for (person, group) in TodoHTMLGrouping.groupByPerson(open) {
            for task in group {
                rows.append(row(task, person: person, includeCompletedDate: false))
            }
        }
        if !done.isEmpty {
            rows.append(["## Abgeschlossen"] + Array(repeating: "", count: header.count - 1))
            for (person, group) in TodoHTMLGrouping.groupByPerson(done) {
                for task in group {
                    rows.append(row(task, person: person, includeCompletedDate: true))
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
        var result: [TodoTask] = []
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
                    changedBy: col(cols, 12)
                )
            )
        }
        return try TodoCodec.makeImportedState(tasks: result)
    }

    private static func row(_ task: TodoTask, person: String, includeCompletedDate: Bool) -> [String] {
        [
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
