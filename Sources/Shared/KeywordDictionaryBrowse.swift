import Foundation

extension KeywordDictionary {
    /// Eine Abteilung mit den zugehörigen Wörtern aus `source` (ohne Duplikate, ohne Leereinträge).
    struct Group: Equatable, Identifiable, Sendable {
        var id: String { dept }
        let dept: String
        let title: String
        let words: [String]
    }

    private static let german = Locale(identifier: "de")

    /// Wörter aus `source`, gruppiert nach `Department.title`, je Abteilung alphabetisch (de).
    static func groups(from source: [String: String], matching query: String = "") -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var remaining = source
        var result: [Group] = []

        func append(deptId: String) {
            guard let csv = remaining.removeValue(forKey: deptId) else { return }
            var seen = Set<String>()
            var words: [String] = []
            for raw in csv.split(separator: ",") {
                let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { continue }
                let key = word.lowercased(with: german)
                guard seen.insert(key).inserted else { continue }
                words.append(word)
            }
            if !needle.isEmpty {
                words.removeAll {
                    $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], locale: german) == nil
                }
            }
            words.sort { $0.compare($1, locale: german) == .orderedAscending }
            guard !words.isEmpty else { return }
            result.append(Group(dept: deptId, title: Department.title(for: deptId), words: words))
        }

        for dept in Department.allCases {
            append(deptId: dept.rawValue)
        }
        for leftover in remaining.keys.sorted() {
            append(deptId: leftover)
        }
        return result
    }
}
