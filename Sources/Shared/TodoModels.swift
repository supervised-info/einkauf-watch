import Foundation

/// Eine Aufgabe wie HTML `todo-v3` (ohne Runtime-`id`).
/// `uid` ist `Int64`, damit watchOS `arm64_32` nicht bei Epoch-Millis crasht.
struct TodoTask: Equatable, Codable, Sendable, Identifiable {
    var uid: Int64
    var text: String
    var completed: Bool
    var prioA: String
    var prioB: String
    var dueDate: String
    var completedDate: String
    var person: String
    var reopenedFromUid: Int64?
    var reopenedToUid: Int64?
    var reopenedAt: String
    var createdAt: String
    var updatedAt: String
    var changedBy: String

    var id: Int64 { uid }

    enum CodingKeys: String, CodingKey {
        case uid, text, completed, prioA, prioB, dueDate, completedDate, person
        case reopenedFromUid, reopenedToUid, reopenedAt, createdAt, updatedAt, changedBy
    }

    init(
        uid: Int64,
        text: String,
        completed: Bool = false,
        prioA: String = "",
        prioB: String = "",
        dueDate: String = "",
        completedDate: String = "",
        person: String = "",
        reopenedFromUid: Int64? = nil,
        reopenedToUid: Int64? = nil,
        reopenedAt: String = "",
        createdAt: String = "",
        updatedAt: String = "",
        changedBy: String = ""
    ) {
        self.uid = uid
        self.text = text
        self.completed = completed
        self.prioA = prioA
        self.prioB = prioB
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.person = person
        self.reopenedFromUid = reopenedFromUid
        self.reopenedToUid = reopenedToUid
        self.reopenedAt = reopenedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.changedBy = changedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = TodoJSON.positiveInt64(c, .uid) ?? 0
        text = (try c.decodeIfPresent(String.self, forKey: .text) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        prioA = TodoJSON.prioA(try c.decodeIfPresent(String.self, forKey: .prioA))
        let rawB = (try? c.decode(String.self, forKey: .prioB))
            ?? (try? c.decode(Int.self, forKey: .prioB)).map(String.init)
        prioB = TodoJSON.prioB(rawB)
        dueDate = TodoJSON.isoDate(try c.decodeIfPresent(String.self, forKey: .dueDate))
        completedDate = TodoJSON.isoDate(try c.decodeIfPresent(String.self, forKey: .completedDate))
        person = try c.decodeIfPresent(String.self, forKey: .person) ?? ""
        reopenedFromUid = TodoJSON.positiveInt64(c, .reopenedFromUid)
        reopenedToUid = TodoJSON.positiveInt64(c, .reopenedToUid)
        reopenedAt = TodoJSON.isoDate(try c.decodeIfPresent(String.self, forKey: .reopenedAt))
        createdAt = TodoJSON.isoTimestamp(try c.decodeIfPresent(String.self, forKey: .createdAt))
        updatedAt = TodoJSON.isoTimestamp(try c.decodeIfPresent(String.self, forKey: .updatedAt))
        changedBy = try c.decodeIfPresent(String.self, forKey: .changedBy) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uid, forKey: .uid)
        try c.encode(text, forKey: .text)
        try c.encode(completed, forKey: .completed)
        try c.encode(prioA, forKey: .prioA)
        try c.encode(prioB, forKey: .prioB)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encode(completedDate, forKey: .completedDate)
        try c.encode(person, forKey: .person)
        try c.encodeIfPresent(reopenedFromUid, forKey: .reopenedFromUid)
        try c.encodeIfPresent(reopenedToUid, forKey: .reopenedToUid)
        try c.encode(reopenedAt, forKey: .reopenedAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(changedBy, forKey: .changedBy)
    }
}

struct TodoState: Equatable, Codable, Sendable {
    var tasks: [TodoTask]
    var nextUid: Int64
    /// Intern (lokales Envelope), analog `listRevision` — nicht im HTML-Export.
    var revision: UInt64

    enum CodingKeys: String, CodingKey {
        case tasks, nextUid, revision
    }

    init(tasks: [TodoTask] = [], nextUid: Int64 = 1, revision: UInt64 = 0) {
        self.tasks = tasks
        self.nextUid = nextUid
        self.revision = revision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TodoTask].self, forKey: .tasks) ?? []
        if let n = try c.decodeIfPresent(Int64.self, forKey: .nextUid) {
            nextUid = max(1, n)
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .nextUid) {
            nextUid = Int64(max(1, n))
        } else {
            nextUid = 1
        }
        revision = try c.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
    }

    static var empty: TodoState { TodoState() }
}

enum TodoJSON {
    static func positiveInt64(_ c: KeyedDecodingContainer<TodoTask.CodingKeys>, _ key: TodoTask.CodingKeys) -> Int64? {
        guard c.contains(key) else { return nil }
        if let v = try? c.decode(Int64.self, forKey: key) { return v > 0 ? v : nil }
        if let v = try? c.decode(Int.self, forKey: key) { return v > 0 ? Int64(v) : nil }
        if let v = try? c.decode(Double.self, forKey: key) {
            let i = Int64(v)
            return i > 0 && Double(i) == v ? i : nil
        }
        if let s = try? c.decode(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let v = Int64(trimmed), v > 0 else { return nil }
            return v
        }
        return nil
    }

    static func prioA(_ raw: String?) -> String {
        guard let s = raw, let ch = s.unicodeScalars.first, s.count == 1,
              ch >= "A" && ch <= "Z" else { return "" }
        return s
    }

    static func prioB(_ raw: String?) -> String {
        guard let s = raw, s.count == 1, let ch = s.first, ("1"..."9").contains(ch) else { return "" }
        return s
    }

    static func isoDate(_ raw: String?) -> String {
        guard let s = raw, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return ""
        }
        return s
    }

    static func isoTimestamp(_ raw: String?) -> String {
        guard let s = raw, !s.isEmpty else { return "" }
        if s.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil { return s }
        if s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return s + "T00:00:00.000Z" }
        return ""
    }
}

enum TodoTime {
    /// Wie HTML `new Date().toISOString()`.
    static func nowIso(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    /// Wie HTML `toISOString().slice(0, 10)` (UTC-Kalendertag).
    static func todayIso(_ date: Date = Date()) -> String {
        String(nowIso(date).prefix(10))
    }
}

enum TodoAuthor {
    static let app = "TS/NA"
}
