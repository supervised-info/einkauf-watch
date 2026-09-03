import SwiftUI
import WatchKit

/// Tap-Mikro: SwiftUI `TextFieldLink` (System-Texteingabe), kein WatchKit-Hosting-Controller.
@MainActor
final class WatchVoiceAddSession: ObservableObject {
    @Published private(set) var status: String?

    private var statusClearTask: Task<Void, Never>?

    func commit(_ text: String, store: ShoppingStore) {
        let count = store.addItems(fromSpeech: text)
        if count > 0 {
            WKInterfaceDevice.current().play(.success)
            showStatus(count == 1 ? "1 Artikel." : "\(count) Artikel.")
        } else {
            showStatus("Nichts verstanden.")
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
struct WatchVoiceAddButton: View {
    @EnvironmentObject private var store: ShoppingStore
    @Environment(\.einkaufTheme) private var theme
    @ObservedObject var session: WatchVoiceAddSession

    var body: some View {
        TextFieldLink(prompt: Text("Artikel diktieren")) {
            Image(systemName: "mic")
                .font(.caption)
                .imageScale(.small)
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        } onSubmit: { text in
            session.commit(text, store: store)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tippen zum Diktieren")
    }
}
