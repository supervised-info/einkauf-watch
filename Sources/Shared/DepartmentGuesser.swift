import Foundation

enum DepartmentGuesser {
    private static let keywords: [(key: String, dept: String)] = {
        var seen = Set<String>()
        var list: [(String, String)] = []
        for (dept, csv) in KeywordDictionary.source {
            for raw in csv.split(separator: ",") {
                let word = canon(raw.trimmingCharacters(in: .whitespaces))
                guard !word.isEmpty, !seen.contains(word) else { continue }
                seen.insert(word)
                list.append((word, dept))
            }
        }
        return list.sorted { $0.0.count > $1.0.count }
    }()

    static func canon(_ s: String) -> String {
        var t = s.lowercased()
        t = t.replacingOccurrences(of: "ä", with: "a")
        t = t.replacingOccurrences(of: "ö", with: "o")
        t = t.replacingOccurrences(of: "ü", with: "u")
        t = t.replacingOccurrences(of: "ß", with: "ss")
        t = t.replacingOccurrences(of: "ae", with: "a")
        t = t.replacingOccurrences(of: "oe", with: "o")
        t = t.replacingOccurrences(of: "ue", with: "u")
        return t
    }

    static func stripQty(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "[-–—]", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\b\d+([.,]\d+)?\s*x\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\b\d+([.,]\d+)?\s*(kg|g|mg|ml|cl|dl|l|stk|stueck|stuck|packung|packungen|pck|pack)\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\b\d+([.,]\d+)?\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\b(kg|g|mg|ml|cl|dl|l|stk|stueck|stuck|packung|packungen|pck|pack|x)\b"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func mappingKey(_ name: String) -> String {
        let c = canon(name.trimmingCharacters(in: .whitespacesAndNewlines))
        let s = stripQty(c)
        return s.isEmpty ? c : s
    }

    static func guess(_ name: String, mappings: [String: String] = [:]) -> String {
        let folded = canon(name)
        let stripped = stripQty(folded)
        let search = stripped.isEmpty ? folded.trimmingCharacters(in: .whitespaces) : stripped
        if search.isEmpty { return Department.sonstiges.rawValue }

        if search.contains("tiefkuhl") || matchesTK(folded) || matchesTK(search) {
            return Department.tiefkuehl.rawValue
        }
        if search.range(of: #"ice\s*tea"#, options: .regularExpression) != nil || search.contains("eistee") {
            return Department.getraenke.rawValue
        }
        if search.range(of: "schorle", options: .regularExpression) != nil
            || search.range(of: #"saft$"#, options: .regularExpression) != nil
            || search == "saft" {
            return Department.getraenke.rawValue
        }
        if search.contains("chips") { return Department.suess.rawValue }
        if search == "eis" || (search.range(of: #"eis$"#, options: .regularExpression) != nil && !search.contains("eisberg")) {
            return Department.tiefkuehl.rawValue
        }

        var best: String?
        var bestLen = 0
        for kw in keywords {
            if kw.key.count < bestLen { break }
            let hit: Bool
            if kw.key.count <= 2 {
                hit = search.range(of: "(^|[^a-z])\(kw.key)([^a-z]|$)", options: .regularExpression) != nil
            } else {
                hit = search.contains(kw.key)
            }
            if hit {
                best = kw.dept
                bestLen = kw.key.count
            }
        }
        if let best { return best }

        let mk = mappingKey(name)
        if let mapped = mappings[mk], Department.isKnown(mapped) { return mapped }
        return Department.sonstiges.rawValue
    }

    private static func matchesTK(_ s: String) -> Bool {
        s.range(of: #"(^|[\s-])tk([\s-]|$)"#, options: .regularExpression) != nil
    }
}
