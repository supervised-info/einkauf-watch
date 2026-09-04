import Foundation

/// Teilt gesprochene oder per Siri gelieferte deutsche Listen in Artikelnamen. Kein NLP: nur einfache Trenner.
/// Mengenwörter bleiben am Namen („zwei Eier“), damit `DepartmentGuesser` weiter greift.
enum SpeechItemSplitter {
    static func items(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var marked = trimmed
        marked = marked.replacingOccurrences(of: ",", with: Self.mark)
        marked = marked.replacingOccurrences(of: ";", with: Self.mark)
        marked = marked.replacingOccurrences(of: "\r\n", with: Self.mark)
        marked = marked.replacingOccurrences(of: "\n", with: Self.mark)
        marked = marked.replacingOccurrences(of: "\r", with: Self.mark)
        marked = marked.replacingOccurrences(
            of: #"\s+und\s+"#,
            with: Self.mark,
            options: [.regularExpression, .caseInsensitive]
        )
        marked = marked.replacingOccurrences(
            of: #"\s+sowie\s+"#,
            with: Self.mark,
            options: [.regularExpression, .caseInsensitive]
        )

        return marked
            .split(separator: Character(Self.mark), omittingEmptySubsequences: true)
            .map { collapseWhitespace(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Siri liefert den Trigger manchmal nochmal im Parameter. Führendes `Einkauf:` / `Einkauf` / `Besorgen:` / `Besorgen`.
    static func strippingTriggerPrefix(_ text: String) -> String {
        stripLeadingTrigger(text, pattern: #"^(?:einkauf|besorgen)(?:\s*:\s*|\s+|$)"#)
    }

    /// To-Do-Siri: führendes `To Do` / `To-Do` / `todo` (nicht `besorgen`).
    static func strippingTodoTriggerPrefix(_ text: String) -> String {
        stripLeadingTrigger(text, pattern: #"^(?:to[\s-]*do|todo)(?:\s*:\s*|\s+|$)"#)
    }

    static func confirmation(addedCount: Int) -> String {
        switch addedCount {
        case 0:
            return "Keine Artikel erkannt."
        case 1:
            return "1 Artikel hinzugefügt."
        default:
            return "\(addedCount) Artikel hinzugefügt."
        }
    }

    static func todoConfirmation(addedCount: Int) -> String {
        switch addedCount {
        case 0:
            return "Keine Aufgaben erkannt."
        case 1:
            return "1 Aufgabe hinzugefügt."
        default:
            return "\(addedCount) Aufgaben hinzugefügt."
        }
    }

    private static func stripLeadingTrigger(_ text: String, pattern: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return trimmed
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let stripped = regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let mark = "\u{1E}"

    private static func collapseWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
