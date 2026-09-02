import Foundation

/// Dateiname und Temp-Datei für „Liste teilen“ (`yyyyMMdd_HHmm-einkauf-{storeSlug}.pdf`).
enum ListShare {
    static func timestamp(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter.string(from: date)
    }

    /// Deutsch-sicherer Slug: Umlaute als ae/oe/ue, ß als ss, sonst ASCII-Buchstaben/Ziffern.
    static func storeSlug(_ name: String) -> String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.lowercased(with: Locale(identifier: "de_DE"))
        let umlauts = [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")]
        for (from, to) in umlauts {
            s = s.replacingOccurrences(of: from, with: to)
        }
        s = s.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var pendingHyphen = false
        for ch in s {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                if pendingHyphen && !out.isEmpty {
                    out.append("-")
                }
                out.append(ch)
                pendingHyphen = false
            } else if !out.isEmpty {
                pendingHyphen = true
            }
        }
        return out.isEmpty ? "laden" : out
    }

    static func stampedFilename(
        storeName: String,
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        "\(timestamp(date: date, timeZone: timeZone))-einkauf-\(storeSlug(storeName)).pdf"
    }

    static func writeTempFile(
        data: Data,
        storeName: String,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            stampedFilename(storeName: storeName, date: date, timeZone: timeZone)
        )
        try data.write(to: url, options: .atomic)
        return url
    }
}
