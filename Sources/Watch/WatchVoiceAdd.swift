import SwiftUI
import WatchKit

/// Tap-Mikro: WatchKit-System-Diktat, kein Speech-Framework, kein Hold-to-Talk.
@MainActor
final class WatchVoiceAddSession: ObservableObject {
    @Published private(set) var isPresenting = false
    @Published private(set) var status: String?

    private var statusClearTask: Task<Void, Never>?

    func tapMic(store: ShoppingStore) {
        guard !isPresenting else { return }
        isPresenting = true
        guard let controller = Self.textInputHost() else {
            isPresenting = false
            showStatus("Diktat nicht bereit.")
            return
        }
        controller.presentTextInputController(
            withSuggestions: nil,
            allowedInputMode: .plain
        ) { [weak self] results in
            Task { @MainActor in
                guard let self else { return }
                self.isPresenting = false
                self.commit(results: results, store: store)
            }
        }
    }

    private func commit(results: [Any]?, store: ShoppingStore) {
        guard results != nil else { return }
        let text = Self.joinedSpeech(from: results)
        let count = store.addItems(fromSpeech: text)
        if count > 0 {
            WKInterfaceDevice.current().play(.success)
            showStatus(count == 1 ? "1 Artikel." : "\(count) Artikel.")
        } else {
            showStatus("Nichts verstanden.")
        }
    }

    /// Mehrere Diktat-Phrasen mit Komma verbinden, damit `SpeechItemSplitter` weiter greift.
    private static func joinedSpeech(from results: [Any]?) -> String {
        guard let results else { return "" }
        return results.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// watchOS 10: `WKApplication` statt deprecated `WKExtension`.
    private static func textInputHost() -> WKInterfaceController? {
        let app = WKApplication.shared()
        return app.visibleInterfaceController ?? app.rootInterfaceController
    }

    private func showStatus(_ text: String) {
        statusClearTask?.cancel()
        status = text
        statusClearTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            if status == text { status = nil }
        }
    }
}

/// Kompaktes Caption-Mikrofon in der Chrome-Zeile — `.plain`, kein title2, kein Toolbar-Kreis.
struct WatchVoiceAddButton: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.einkaufTheme) private var theme
    @ObservedObject var session: WatchVoiceAddSession

    var body: some View {
        Button {
            session.tapMic(store: store)
        } label: {
            Image(systemName: session.isPresenting ? "mic.fill" : "mic")
                .font(.caption)
                .imageScale(.small)
                .foregroundStyle(session.isPresenting ? theme.oxide : theme.muted)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.isPresenting ? "Diktat läuft" : "Tippen zum Diktieren")
        .disabled(session.isPresenting)
    }
}
