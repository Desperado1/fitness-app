import Foundation

/// Offline speech used when the app is launched with `-mock-voice`: the
/// simulator has no usable microphone, so CI drives the voice loop with a
/// canned script instead. Same role `MockLLMClient` plays for the coach.
///
/// The utterances match `MockLLMClient`'s scripted check-in, so the two
/// mocks together walk a complete hands-free conversation.
final class ScriptedSpeechEngine: SpeechEngine {
    private let utterances: [String]
    private var index = 0
    private var pendingWork: [DispatchWorkItem] = []

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

        // Emit a partial first, then finish, so the live-transcript UI and
        // the phase transitions are exercised the same way as for real.
        schedule(after: 0.3) { onPartial(String(text.prefix(text.count / 2))) }
        schedule(after: 0.7) { onFinal(text) }
    }

    func stopTranscribing() {
        cancelPending()
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        // Short but non-zero, so the speaking phase is visible in screenshots.
        schedule(after: 0.4) { completion() }
    }

    func stopSpeaking() {
        cancelPending()
    }

    private func cancelPending() {
        for work in pendingWork { work.cancel() }
        pendingWork.removeAll()
    }

    private func schedule(after delay: TimeInterval, _ body: @escaping () -> Void) {
        let work = DispatchWorkItem(block: body)
        pendingWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
