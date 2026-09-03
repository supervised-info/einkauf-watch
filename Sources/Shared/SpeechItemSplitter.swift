import Foundation

/// Teilt gesprochene deutsche Listen in Artikelnamen. Kein NLP: nur einfache Trenner.
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

    private static let mark = "\u{1E}"

    private static func collapseWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
