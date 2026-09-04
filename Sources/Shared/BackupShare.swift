import Foundation

enum BackupShare {
    static let einkaufStem = "einkauf-backup"
    static let todoStem = "todo-liste"

    /// Wie HTML `stampedFilename`: `yyyyMMdd_HHmm-{stem}.json`.
    /// Einkauf-Default `einkauf-backup`; To-Do `todo-liste`.
    static func stampedFilename(
        stem: String = einkaufStem,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "\(formatter.string(from: date))-\(stem).json"
    }

    static func writeTempFile(
        data: Data,
        stem: String = einkaufStem,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            stampedFilename(stem: stem, date: date, timeZone: timeZone)
        )
        try data.write(to: url, options: .atomic)
        return url
    }
}
