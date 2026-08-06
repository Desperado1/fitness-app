import Foundation

/// Where the voice loop currently is. Drives the whole voice UI from one
/// value, so the orb, the transcript and the controls can never disagree.
enum VoicePhase {
    case idle
    case listening
    /// Waiting on the coach — the LLM call is in flight.
    case thinking
    case speaking
}

/// The platform half of voice: microphone, transcription, speech synthesis.
///
/// Behind a protocol because audio does not work meaningfully in the
/// simulator. CI drives the whole flow with scripted speech instead, which
/// is the only way this feature stays visible to the Mac-less workflow.
protocol SpeechEngine: AnyObject {
    /// True once the microphone and speech recognition are both permitted.
    func requestPermissions() async -> Bool

    func startTranscribing(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    )
    func stopTranscribing()

    func speak(_ text: String, completion: @escaping () -> Void)
    func stopSpeaking()
}

/// Scripted speech under `-mock-voice` (UI tests), the real thing otherwise.
func makeSpeechEngine() -> any SpeechEngine {
    if ProcessInfo.processInfo.arguments.contains("-mock-voice") {
        return ScriptedSpeechEngine()
    }
    return SystemSpeechEngine()
}

/// Drives the hands-free loop: speak → listen → detect the end of a
/// sentence → hand the text to the coach → speak the reply → listen again.
///
/// Policy lives here (when an utterance is finished, what the phases are);
/// mechanism lives in `SpeechEngine`. That split is what makes the timing
/// testable without a microphone.
@MainActor
final class VoiceSession: ObservableObject {
    @Published private(set) var phase: VoicePhase = .idle
    /// What the recognizer has heard so far this turn, updated live.
    @Published private(set) var partialTranscript = ""
    @Published var errorMessage: String?
    /// Set when the client has refused the mic or speech permission — the
    /// caller falls back to typing rather than nagging.
    @Published private(set) var permissionDenied = false

    /// How long a pause ends a turn. The single most important number in
    /// the feature: too short cuts people off mid-thought, too long makes
    /// every exchange drag.
    static let silenceInterval: TimeInterval = 1.0

    private let engine: any SpeechEngine
    private var silenceTimer: Timer?
    private var onUtterance: ((String) -> Void)?
    /// Guards against the recognizer's final result and the silence timer
    /// both submitting the same turn.
    private var hasSubmittedThisTurn = false

    init(engine: (any SpeechEngine)? = nil) {
        self.engine = engine ?? makeSpeechEngine()
    }

    var isListening: Bool {
        if case .listening = phase { return true }
        return false
    }

    /// Asks for permissions once. Returns false if either was refused, in
    /// which case voice stays off and the typed path carries on.
    func prepare() async -> Bool {
        let granted = await engine.requestPermissions()
        permissionDenied = !granted
        return granted
    }

    /// Speaks a line and returns when it has finished, so the caller can
    /// sequence "say this, then listen" without callbacks.
    func speak(_ text: String) async {
        guard !text.isEmpty else { return }
        phase = .speaking
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.speak(text) {
                continuation.resume()
            }
        }
        if case .speaking = phase { phase = .idle }
    }

    /// Starts a listening turn. `handler` fires once, with the completed
    /// utterance, when the client stops talking.
    func listen(_ handler: @escaping (String) -> Void) {
        stopListening()
        onUtterance = handler
        hasSubmittedThisTurn = false
        partialTranscript = ""
        phase = .listening

        engine.startTranscribing(
            // Recognition callbacks arrive on an arbitrary queue, so every
            // one of them hops back before touching session state.
            onPartial: { [weak self] text in
                Task { @MainActor in self?.handlePartial(text) }
            },
            onFinal: { [weak self] text in
                Task { @MainActor in self?.handleFinal(text) }
            },
            onError: { [weak self] message in
                Task { @MainActor in self?.handleError(message) }
            }
        )
    }

    /// Ends the listening turn without submitting anything.
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        engine.stopTranscribing()
        if case .listening = phase { phase = .idle }
    }

    /// Ends everything — used when the client leaves voice mode or the
    /// sheet goes away, so the microphone is never left open.
    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        onUtterance = nil
        engine.stopTranscribing()
        engine.stopSpeaking()
        partialTranscript = ""
        phase = .idle
    }

    /// Called by the owner once the coach's answer is on its way, so the
    /// orb shows thinking rather than an idle mic.
    func markThinking() {
        phase = .thinking
    }

    func markIdle() {
        phase = .idle
    }

    // MARK: - Turn detection

    private func handlePartial(_ text: String) {
        guard !hasSubmittedThisTurn else { return }
        partialTranscript = text
        restartSilenceTimer()
    }

    private func handleFinal(_ text: String) {
        guard !hasSubmittedThisTurn else { return }
        partialTranscript = text
        submit()
    }

    private func handleError(_ message: String) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        engine.stopTranscribing()
        errorMessage = message
        phase = .idle
    }

    /// A pause resets on every new word, so the turn ends only after the
    /// client has actually stopped — not after a fixed window.
    private func restartSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: Self.silenceInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.submit() }
        }
    }

    private func submit() {
        guard !hasSubmittedThisTurn else { return }
        hasSubmittedThisTurn = true

        silenceTimer?.invalidate()
        silenceTimer = nil
        engine.stopTranscribing()

        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        phase = .thinking
        let handler = onUtterance
        onUtterance = nil
        handler?(text)
    }
}
