import Foundation

/// Where the voice loop currently is. Drives the whole voice UI from one
/// value, so the orb, the transcript and the controls can never disagree.
enum VoicePhase: Equatable {
    case idle
    case listening
    /// Waiting on the coach — the LLM call is in flight. The coach may well
    /// be saying a filler line during this phase; it is still thinking, and
    /// the orb should not claim to be delivering a reply that hasn't landed.
    case thinking
    case speaking
}

/// The platform half of voice: microphone, transcription, speech synthesis.
///
/// Behind a protocol because audio does not work meaningfully in the
/// simulator. CI drives the whole flow with scripted speech instead, which
/// is the only way this feature stays visible to the Mac-less workflow.
protocol SpeechEngine: AnyObject {
    /// Live loudness, 0–1, of whichever side is currently making sound —
    /// the client while transcribing, the coach while speaking. Decorative:
    /// it drives the orb and nothing else, so an engine is free to
    /// approximate it.
    var onLevel: ((Float) -> Void)? { get set }

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
    /// Loudness of whoever is currently talking, 0–1, smoothed. The orb
    /// deforms to this; it is the main signal that the loop is alive.
    @Published private(set) var level: Double = 0
    /// A short line for the client when a turn produced nothing at all —
    /// silence with no explanation looks like the app died.
    @Published private(set) var notice: String?
    @Published var errorMessage: String?
    /// Set when the client has refused the mic or speech permission — the
    /// caller falls back to typing rather than nagging.
    @Published private(set) var permissionDenied = false

    /// How long a pause ends a turn. The single most important number in
    /// the feature: too short cuts people off mid-thought, too long makes
    /// every exchange drag.
    static let silenceInterval: TimeInterval = 1.0

    /// Weight of each new sample in the level EMA. Low enough that the orb
    /// glides through the gaps between syllables rather than strobing.
    private static let levelSmoothing = 0.4

    private let engine: any SpeechEngine
    private var silenceTimer: Timer?
    private var onUtterance: ((String) -> Void)?
    /// Guards against the recognizer's final result and the silence timer
    /// both submitting the same turn.
    private var hasSubmittedThisTurn = false
    private var filler = ThinkingFiller()
    /// Empty turns re-arm the microphone rather than dying quietly, but not
    /// forever: a recognizer that keeps returning nothing instantly would
    /// spin, and at that point something is wrong that another turn won't fix.
    private var consecutiveEmptyTurns = 0
    private static let maxConsecutiveEmptyTurns = 3

    init(engine: (any SpeechEngine)? = nil) {
        let engine = engine ?? makeSpeechEngine()
        self.engine = engine
        // Levels arrive from the audio thread, so they hop back like every
        // other engine callback.
        engine.onLevel = { [weak self] value in
            Task { @MainActor in self?.applyLevel(value) }
        }
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
        await rawSpeak(text)
        if case .speaking = phase { phase = .idle }
    }

    /// Says a short filler line *over* the model round trip, so the wait
    /// sounds like thought instead of lag. The caller must already have
    /// started the coach's task — this is meant to overlap it, not precede
    /// it, or it just adds latency of its own.
    ///
    /// Phase deliberately stays `.thinking`: the answer genuinely hasn't
    /// arrived, and the orb shouldn't imply otherwise.
    func fillThinkingPause() async {
        phase = .thinking
        await rawSpeak(filler.next())
    }

    /// Cuts the coach off mid-sentence. The synthesizer's cancel callback
    /// resolves the continuation inside `rawSpeak`, so whoever is awaiting
    /// `speak` simply walks on to the next step of the loop.
    func interruptSpeaking() {
        engine.stopSpeaking()
    }

    /// Speaks without touching `phase`, so callers decide what the orb says
    /// they're doing.
    private func rawSpeak(_ text: String) async {
        guard !text.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.speak(text) {
                continuation.resume()
            }
        }
        resetLevel()
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
        resetLevel()
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
        notice = nil
        consecutiveEmptyTurns = 0
        resetLevel()
        phase = .idle
    }

    /// Dictation ends the turn without a coach behind it, so the caller
    /// puts the orb back itself (see `ChatView`).
    func markIdle() {
        phase = .idle
    }

    // MARK: - Turn detection

    private func handlePartial(_ text: String) {
        guard !hasSubmittedThisTurn else { return }
        // Words are landing again, so any "didn't catch that" has served
        // its purpose — and the microphone is demonstrably working.
        notice = nil
        consecutiveEmptyTurns = 0
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
        resetLevel()
        errorMessage = message
        phase = .idle
    }

    private func applyLevel(_ value: Float) {
        level = level * (1 - Self.levelSmoothing) + Double(value) * Self.levelSmoothing
    }

    private func resetLevel() {
        level = 0
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
        resetLevel()

        let text = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // Nothing was heard. Silence must never reach the coach as if
            // the client had spoken — but dropping to idle strands them in
            // a dead loop that looks like a crash, so the turn re-arms with
            // the same handler and says why.
            consecutiveEmptyTurns += 1
            guard let handler = onUtterance,
                  consecutiveEmptyTurns < Self.maxConsecutiveEmptyTurns
            else {
                notice = "I'm not hearing anything — tap to try again."
                phase = .idle
                return
            }
            listen(handler)
            notice = "Didn't catch that — have another go."
            return
        }
        consecutiveEmptyTurns = 0
        notice = nil
        phase = .thinking
        let handler = onUtterance
        onUtterance = nil
        handler?(text)
    }
}
