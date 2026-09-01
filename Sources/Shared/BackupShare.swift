import Foundation

enum BackupShare {
    /// Wie HTML `stampedFilename("einkauf-backup.json")`: `yyyyMMdd_HHmm-einkauf-backup.json`.
    static func stampedFilename(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "\(formatter.string(from: date))-einkauf-backup.json"
    }

    static func writeTempFile(
        data: Data,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(stampedFilename(date: date, timeZone: timeZone))
        try data.write(to: url, options: .atomic)
        return url
    }
}
