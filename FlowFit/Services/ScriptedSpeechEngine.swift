import Foundation

/// Offline speech used when the app is launched with `-mock-voice`: the
/// simulator has no usable microphone, so CI drives the voice loop with a
/// canned script instead. Same role `MockLLMClient` plays for the coach.
///
/// The utterances match `MockLLMClient`'s scripted check-in, so the two
/// mocks together walk a complete hands-free conversation.
final class ScriptedSpeechEngine: SpeechEngine {
    /// Synthetic loudness while "talking". Without it CI screenshots show a
    /// dead orb, and the amplitude-reactive orb is the headline of the
    /// feature — the one thing the Mac-less workflow most needs to see.
    var onLevel: ((Float) -> Void)?

    private let utterances: [String]
    private var index = 0
    private var transcriptionWork: [DispatchWorkItem] = []
    private var speechWork: DispatchWorkItem?
    /// Held rather than fired-and-forgotten so `stopSpeaking` can resolve it,
    /// exactly as the real synthesizer's `didCancel` does. A cancelled
    /// utterance that never completes would suspend the voice loop forever.
    private var speechCompletion: (() -> Void)?
    private var levelWork: DispatchWorkItem?

    /// Roughly matches the real engine's ~14 Hz level rate.
    private static let levelInterval: TimeInterval = 0.07

    init(utterances: [String] = [
        "Pretty tired, and my calves are sore",
        "At home, about half an hour",
    ]) {
        self.utterances = utterances
    }

    func requestPermissions() async -> Bool { true }

    func startTranscribing(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard index < utterances.count else {
            // Script exhausted: stay silent rather than looping, so a test
            // that goes off-script fails visibly instead of spinning.
            return
        }
        let text = utterances[index]
        index += 1

        startEmittingLevels()
        // Emit a partial first, then finish, so the live-transcript UI and
        // the phase transitions are exercised the same way as for real.
        transcriptionWork.append(schedule(after: 0.3) { onPartial(String(text.prefix(text.count / 2))) })
        transcriptionWork.append(schedule(after: 0.7) { [weak self] in
            self?.stopEmittingLevels()
            onFinal(text)
        })
    }

    func stopTranscribing() {
        for work in transcriptionWork { work.cancel() }
        transcriptionWork.removeAll()
        stopEmittingLevels()
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        // A second utterance replaces the first, like the real synthesizer
        // being stopped — never leave the earlier caller suspended.
        finishSpeaking()

        speechCompletion = completion
        startEmittingLevels()
        // Short but non-zero, so the speaking phase is visible in screenshots.
        speechWork = schedule(after: 0.4) { [weak self] in self?.finishSpeaking() }
    }

    func stopSpeaking() {
        finishSpeaking()
    }

    private func finishSpeaking() {
        speechWork?.cancel()
        speechWork = nil
        stopEmittingLevels()

        let completion = speechCompletion
        speechCompletion = nil
        completion?()
    }

    // MARK: - Levels

    private func startEmittingLevels() {
        guard levelWork == nil else { return }
        emitLevel()
    }

    private func stopEmittingLevels() {
        levelWork?.cancel()
        levelWork = nil
        onLevel?(0)
    }

    /// Re-armed one tick at a time rather than on a repeating timer, so a
    /// stop takes effect immediately and nothing outlives the engine.
    private func emitLevel() {
        onLevel?(Float.random(in: 0.35...0.95))
        levelWork = schedule(after: Self.levelInterval) { [weak self] in
            guard let self, self.levelWork != nil else { return }
            self.emitLevel()
        }
    }

    @discardableResult
    private func schedule(after delay: TimeInterval, _ body: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: body)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }
}
