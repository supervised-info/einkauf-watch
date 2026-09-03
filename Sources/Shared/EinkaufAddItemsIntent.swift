#if canImport(AppIntents)
import AppIntents
import Foundation

/// Siri / Kurzbefehl: Phrase mit App-Namen + **besorgen**; Siri fragt danach nach Artikeln.
struct EinkaufAddItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Artikel hinzufügen"
    static var description = IntentDescription("Fügt Artikel zur Einkaufsliste hinzu.")
#if os(watchOS)
    static var openAppWhenRun = true
#else
    static var openAppWhenRun = false
#endif

    @Parameter(title: "Artikel", requestValueDialog: "Was soll ich besorgen?")
    var items: String

    static var parameterSummary: some ParameterSummary {
        Summary("Besorgen \(\.$items)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let speech = SpeechItemSplitter.strippingTriggerPrefix(items)
#if os(watchOS)
            // Kein ShoppingStore / kein AppState-Encode im Siri-Prozess — sonst „Irgendwas hat nicht geklappt.“
            SiriPendingAdds.enqueue(speech)
            if speech.isEmpty {
                return .result(dialog: IntentDialog("Alles klar."))
            }
            return .result(dialog: IntentDialog("Wird zur Liste hinzugefügt."))
#else
            let store = ShoppingStore(enableSync: true)
            let count = store.addItems(fromSpeech: speech)
            let message = SpeechItemSplitter.confirmation(addedCount: count)
            return .result(dialog: IntentDialog("\(message)"))
#endif
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
