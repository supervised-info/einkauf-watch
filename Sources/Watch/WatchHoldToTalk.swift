import AVFoundation
import Speech
import SwiftUI
import WatchKit

/// Hold-to-Talk: Sprache nur solange der Finger auf dem Mikrofon liegt.
@MainActor
final class WatchHoldToTalkSession: ObservableObject {
    @Published private(set) var isHolding = false
    @Published private(set) var status: String?

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var generation = 0
    private var tapInstalled = false
    private var statusClearTask: Task<Void, Never>?

    func pressBegan() {
        guard !isHolding else { return }
        isHolding = true
        transcript = ""
        generation += 1
        let token = generation
        Task { await start(token: token) }
    }

    func pressEnded(store: ShoppingStore) {
        let wasHolding = isHolding
        isHolding = false
        generation += 1
        let text = transcript
        stopEngine(cancel: SpeechItemSplitter.items(from: text).isEmpty)
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
            stopEngine(cancel: true)
            showStatus(denied)
            return
        }
        guard isHolding, generation == token else { return }
        do {
            try beginRecognition()
        } catch {
            guard generation == token else { return }
            isHolding = false
            stopEngine(cancel: true)
            showStatus("Mikrofon nicht bereit.")
        }
    }

    private func permissionStatus() async -> String? {
        switch await speechStatus() {
        case .authorized:
            break
        case .denied, .restricted:
            return "Spracherkennung nicht erlaubt."
        case .notDetermined:
            return "Spracherkennung nicht erlaubt."
        @unknown default:
            return "Spracherkennung nicht erlaubt."
        }
        if await microphoneGranted() { return nil }
        return "Mikrofon nicht erlaubt."
    }

    private func speechStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func microphoneGranted() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func beginRecognition() throws {
        stopEngine(cancel: true)
        guard let recognizer = Self.preferredRecognizer() else {
            throw RecognitionError.unavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        engine.prepare()
        var format = input.outputFormat(forBus: 0)
        if format.sampleRate == 0 || format.channelCount == 0 {
            guard let fallback = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
                throw RecognitionError.unavailable
            }
            format = fallback
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        audioEngine = engine
        self.request = request
        try engine.start()

        transcript = ""
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
            }
        }
    }

    private func stopEngine(cancel: Bool) {
        request?.endAudio()
        if cancel {
            task?.cancel()
        } else {
            task?.finish()
        }
        task = nil
        request = nil
        if let engine = audioEngine {
            engine.stop()
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
        }
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    /// `de_DE` zuerst, sonst Geräte-Locale.
    static func preferredRecognizer() -> SFSpeechRecognizer? {
        if let german = SFSpeechRecognizer(locale: Locale(identifier: "de_DE")) {
            return german
        }
        return SFSpeechRecognizer(locale: Locale.current)
    }

    private enum RecognitionError: Error {
        case unavailable
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
