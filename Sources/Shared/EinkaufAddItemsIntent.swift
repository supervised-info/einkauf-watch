#if canImport(AppIntents)
import AppIntents
import Foundation

/// Siri / Kurzbefehl: Phrase mit App-Namen + **besorgen**; Siri fragt danach nach Artikeln.
struct EinkaufAddItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Artikel hinzufügen"
    static var description = IntentDescription("Fügt Artikel zur Einkaufsliste hinzu.")
    static var openAppWhenRun = false

    @Parameter(title: "Artikel", requestValueDialog: "Was soll ich besorgen?")
    var items: String

    static var parameterSummary: some ParameterSummary {
        Summary("Besorgen \(\.$items)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let speech = SpeechItemSplitter.strippingTriggerPrefix(items)
            let count: Int
#if os(watchOS)
            // Kein WCSession.activate / WidgetKit im Siri-Prozess — sonst „Irgendwas hat nicht geklappt.“
            let store = ShoppingStore(enableSync: false)
            count = try store.addItemsFromSiri(speech)
#else
            let store = ShoppingStore(enableSync: true)
            count = store.addItems(fromSpeech: speech)
#endif
            let message = SpeechItemSplitter.confirmation(addedCount: count)
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            return .result(dialog: IntentDialog("Speichern fehlgeschlagen."))
        }
    }
}

struct EinkaufShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EinkaufAddItemsIntent(),
            phrases: [
                "\(.applicationName) besorgen",
                "Besorgen mit \(.applicationName)",
                "\(.applicationName) zum Besorgen",
            ],
            shortTitle: "Besorgen",
            systemImageName: "cart.badge.plus"
        )
    }
}
#endif
