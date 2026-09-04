#if canImport(AppIntents)
import AppIntents
import Foundation

/// Siri / Kurzbefehl: Phrase mit App-Namen + **To Do**; Siri fragt danach **„T“**.
/// AppShortcut steht in `EinkaufShortcuts` (Apple: nur ein Provider pro App).
struct TodoAddItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Aufgaben hinzufügen"
    static var description = IntentDescription("Fügt Aufgaben zur To-Do-Liste hinzu.")
    static var openAppWhenRun = false

    @Parameter(title: "Aufgaben", requestValueDialog: "T")
    var items: String

    static var parameterSummary: some ParameterSummary {
        Summary("To Do \(\.$items)")
    }

#if os(watchOS)
    @MainActor
    func perform() async -> some IntentResult {
        let speech = SpeechItemSplitter.strippingTodoTriggerPrefix(items)
        TodoSiriPendingAdds.enqueue(speech)
        return .result()
    }
#else
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let speech = SpeechItemSplitter.strippingTodoTriggerPrefix(items)
            let store = TodoStore(enableSync: true)
            let count = store.addItems(fromSpeech: speech)
            let message = SpeechItemSplitter.todoConfirmation(addedCount: count)
            return .result(dialog: IntentDialog("\(message)"))
        } catch {
            return .result(dialog: IntentDialog("Speichern fehlgeschlagen."))
        }
    }
#endif
}
#endif
