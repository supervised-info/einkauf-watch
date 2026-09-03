#if canImport(AppIntents)
import AppIntents
import Foundation

/// Siri / Kurzbefehl: „Einkauf …“ / „Einkauf: …“ fügt Artikel zur Liste hinzu.
struct EinkaufAddItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Artikel hinzufügen"
    static var description = IntentDescription("Fügt Artikel zur Einkaufsliste hinzu.")
    static var openAppWhenRun = false

    @Parameter(title: "Artikel", requestValueDialog: "Welche Artikel?")
    var items: String

    static var parameterSummary: some ParameterSummary {
        Summary("Einkauf \(\.$items)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = ShoppingStore(enableSync: true)
        let count = store.addItems(fromSpeech: items)
        let message = SpeechItemSplitter.confirmation(addedCount: count)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct EinkaufShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EinkaufAddItemsIntent(),
            phrases: [
                "Einkauf \(\.$items)",
                "Einkauf: \(\.$items)",
                "\(.applicationName) Einkauf \(\.$items)",
                "\(.applicationName) Einkauf: \(\.$items)",
                "\(.applicationName) \(\.$items)",
            ],
            shortTitle: "Einkauf",
            systemImageName: "cart.badge.plus"
        )
    }
}
#endif
