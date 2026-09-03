import SwiftUI
import WatchKit

/// Hold-to-Talk: Sprache nur solange der Finger auf dem Mikrofon liegt.
/// Speech/AVFoundation laufen im ObjC-Shim `WatchSpeechRecognizer` — kein Swift-`import Speech`.
@MainActor
final class WatchHoldToTalkSession: ObservableObject {
    @Published private(set) var isHolding = false
    @Published private(set) var status: String?

    private let recognizer = WatchSpeechRecognizer()
    private var generation = 0
    private var statusClearTask: Task<Void, Never>?

    func pressBegan() {
        guard !isHolding else { return }
        isHolding = true
        generation += 1
        let token = generation
        Task { await start(token: token) }
    }

    func pressEnded(store: ShoppingStore) {
        let wasHolding = isHolding
        isHolding = false
        generation += 1
        let text = recognizer.transcript
        recognizer.stop(canceling: SpeechItemSplitter.items(from: text).isEmpty)
        guard wasHolding else { return }

        let count = store.addItems(fromSpeech: text)
        if count > 0 {
            WKInterfaceDevice.current().play(.success)
            showStatus(count == 1 ? "1 Artikel." : "\(count) Artikel.")
        } else {
            showStatus("Nichts verstanden.")
        }
    }

    private func start(token: Int) async {
        if let denied = await permissionStatus() {
            guard isHolding, generation == token else { return }
            isHolding = false
            recognizer.stop(canceling: true)
            showStatus(denied)
            return
        }
        guard isHolding, generation == token else { return }
        do {
            try recognizer.start()
        } catch {
            guard generation == token else { return }
            isHolding = false
            recognizer.stop(canceling: true)
            showStatus("Mikrofon nicht bereit.")
        }
    }

    private func permissionStatus() async -> String? {
        await withCheckedContinuation { continuation in
            recognizer.requestPermissions { granted, denial in
                if granted {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: denial)
                }
            }
        }
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
struct WatchHoldToTalkButton: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.einkaufTheme) private var theme
    @ObservedObject var session: WatchHoldToTalkSession

    var body: some View {
        Button(action: {}) {
            Image(systemName: session.isHolding ? "mic.fill" : "mic")
                .font(.caption)
                .imageScale(.small)
                .foregroundStyle(session.isHolding ? theme.oxide : theme.muted)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.isHolding ? "Loslassen zum Hinzufügen" : "Gedrückt halten zum Sprechen")
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 80, pressing: { pressing in
            if pressing {
                session.pressBegan()
            } else {
                session.pressEnded(store: store)
            }
        }, perform: {})
    }
}
