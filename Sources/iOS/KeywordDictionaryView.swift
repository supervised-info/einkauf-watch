import SwiftUI

/// Nur lesen: lokales `KeywordDictionary.source`, keine Netzabfrage, keine Bearbeitung.
struct KeywordDictionaryView: View {
    @Environment(\.einkaufTheme) private var theme
    @State private var query = ""

    private var groups: [KeywordDictionary.Group] {
        KeywordDictionary.groups(from: KeywordDictionary.source, matching: query)
    }

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.words, id: \.self) { word in
                        Text(word)
                            .einkaufRowChrome()
                    }
                } header: {
                    Text(group.title)
                        .foregroundStyle(theme.muted)
                }
            }
            Section {
            } footer: {
                Text("Zuordnung beim Tippen läuft nur lokal. Sonderregeln (TK, Eistee, Schorle, Chips, Eis) stehen nicht in dieser Liste. Eigene Korrekturen merkt sich die App unter dem Artikelnamen (ohne Menge) und nutzt sie beim nächsten Eintragen; das Wörterbuch selbst ändert sich nicht.")
            }
        }
        .einkaufListChrome()
        .navigationTitle("Wörterbuch")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Wort suchen")
    }
}

#Preview {
    NavigationStack {
        KeywordDictionaryView()
    }
    .environment(\.einkaufTheme, ThemeTokens.make(palette: .vintage, scheme: .light))
}
