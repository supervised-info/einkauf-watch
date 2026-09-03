import SwiftUI
import WatchKit

/// Tap-Mikro: In-App-TextField-Panel (Scribble/Diktat über die Systemsteuerung des Felds).
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
    @Environment(\.einkaufTheme) private var theme
    @Binding var showDictate: Bool

    var body: some View {
        Button {
            showDictate = true
        } label: {
            Image(systemName: showDictate ? "mic.fill" : "mic")
                .font(.caption)
                .imageScale(.small)
                .foregroundStyle(showDictate ? theme.oxide : theme.muted)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(showDictate)
        .accessibilityLabel("Tippen zum Diktieren")
    }
}

/// In-App-Feld statt System-Text-Modal: Commit erst nach **Übernehmen**.
struct WatchDictatePanel: View {
    @Environment(\.einkaufTheme) private var theme
    @Binding var text: String
    var onCancel: () -> Void
    var onCommit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .imageScale(.small)
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abbrechen")
                Spacer()
            }
            .frame(height: 20)

            TextField("Artikel", text: $text)
                .focused($focused)
                .font(.caption)
                .foregroundStyle(theme.ink)

            Button("Übernehmen", action: onCommit)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(theme.oxide)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Übernehmen")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }
}
