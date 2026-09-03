#if canImport(AppIntents)
import AppIntents
import Foundation

/// Siri / Kurzbefehl: Phrase mit App-Namen + **besorgen**; Siri fragt danach nach Artikeln.
struct EinkaufAddItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Artikel hinzufügen"
    static var description = IntentDescription("Fügt Artikel zur Einkaufsliste hinzu.")
    /// Watch und iPhone: Siri nicht zum App-Start zwingen — `true` bricht auf der Watch oft still ab.
    static var openAppWhenRun = false

    @Parameter(title: "Artikel", requestValueDialog: "ok")
    var items: String

    static var parameterSummary: some ParameterSummary {
        Summary("Besorgen \(\.$items)")
    }

#if os(watchOS)
    @MainActor
    func perform() async -> some IntentResult {
        let speech = SpeechItemSplitter.strippingTriggerPrefix(items)
        SiriPendingAdds.enqueue(speech)
        return .result()
    }
#else
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let speech = SpeechItemSplitter.strippingTriggerPrefix(items)
            let store = ShoppingStore(enableSync: true)
            let count = store.addItems(fromSpeech: speech)
            let message = SpeechItemSplitter.confirmation(addedCount: count)
            return .result(dialog: IntentDialog("\(message)"))
        } catch {
            return .result(dialog: IntentDialog("Speichern fehlgeschlagen."))
        }
    }
#endif
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
