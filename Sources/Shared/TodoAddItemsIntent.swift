#if canImport(AppIntents)
import AppIntents
import Foundation

/// Siri / Kurzbefehl: Phrase mit App-Namen + **Todo** (ein Token, nicht „To Do“);
/// `shortTitle` ebenfalls **Todo** (Watch-Siri keyed oft darauf — zwei Tokens cappt Diktat).
/// iPhone: Siri fragt **„o“**. watchOS: kein `requestValueDialog` (generische Freitext-Nachfrage;
/// Custom-Dialog filtert/kürzt Free-Form auf der Watch).
/// AppShortcut steht in `EinkaufShortcuts` (Apple: nur ein Provider pro App).
struct TodoAddItemsIntent: AppIntent {
    static var title: LocalizedStringResource = "Aufgaben hinzufügen"
    static var description = IntentDescription("Fügt Aufgaben zur To-Do-Liste hinzu.")
    static var openAppWhenRun = false

#if os(watchOS)
    @Parameter(
        title: "Aufgaben",
        inputOptions: String.IntentInputOptions(capitalizationType: .sentences, multiline: true)
    )
    var items: String
#else
    @Parameter(
        title: "Aufgaben",
        inputOptions: String.IntentInputOptions(capitalizationType: .sentences, multiline: true),
        requestValueDialog: "o"
    )
    var items: String
#endif

    static var parameterSummary: some ParameterSummary {
        Summary("Todo \(\.$items)")
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
