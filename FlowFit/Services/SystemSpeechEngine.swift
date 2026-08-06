import AVFoundation
import Foundation
import Speech

/// Real speech I/O: `SFSpeechRecognizer` in, `AVSpeechSynthesizer` out.
///
/// The session listens and speaks in turns rather than at once. Keeping the
/// microphone open while the coach talks would need echo cancellation to
/// stop it transcribing its own voice, so listening is paused during
/// playback — barge-in is deliberately out of scope for now.
final class SystemSpeechEngine: SpeechEngine {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let synthesizerDelegate = SpeechCompletionDelegate()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isTapInstalled = false

    init() {
        synthesizer.delegate = synthesizerDelegate
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Listening

    func startTranscribing(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let recognizer, recognizer.isAvailable else {
            onError("Speech recognition isn't available right now.")
            return
        }
        stopTranscribing()

        do {
            try configureSession()

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            // Bound as a local so the audio thread appends without hopping
            // back to the main actor for every buffer.
            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            isTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()

            // These callbacks arrive on an arbitrary queue; the handlers
            // passed in by VoiceSession hop to the main actor themselves.
            task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        onFinal(text)
                    } else {
                        onPartial(text)
                    }
                } else if error != nil {
                    onError("I couldn't quite catch that — try again, or type instead.")
                }
            }
        } catch {
            stopTranscribing()
            onError(error.localizedDescription)
        }
    }

    func stopTranscribing() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
    }

    // MARK: - Speaking

    func speak(_ text: String, completion: @escaping () -> Void) {
        do {
            try configureSession()
        } catch {
            // Speech is a nicety; a session that won't configure shouldn't
            // strand the caller waiting for a completion that never comes.
            completion()
            return
        }

        synthesizerDelegate.onFinish = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestAvailableVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Audio session

    /// One category for the whole loop. Switching between record and
    /// playback per turn audibly clicks and costs time on every exchange.
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Voice selection

    /// Picks the best-sounding installed voice for the user's language.
    /// The compact default is noticeably robotic, and a robotic coach
    /// undermines the whole point — enhanced and premium voices are much
    /// better but have to be downloaded on the device first.
    static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        let best = candidates.max { quality($0.quality) < quality($1.quality) }
        return best ?? AVSpeechSynthesisVoice(language: language)
    }

    /// True when only the basic voice is installed, so Settings can point
    /// the client at iOS's voice download rather than leaving them
    /// wondering why the coach sounds like that.
    static var hasOnlyCompactVoice: Bool {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .allSatisfy { quality($0.quality) == 0 }
    }

    private static func quality(_ value: AVSpeechSynthesisVoiceQuality) -> Int {
        switch value {
        case .premium: return 2
        case .enhanced: return 1
        default: return 0
        }
    }
}

/// Separate, non-isolated delegate so `AVSpeechSynthesizerDelegate`'s
/// nonisolated requirements can be satisfied without opening holes in
/// `SystemSpeechEngine`'s main-actor isolation.
private final class SpeechCompletionDelegate: NSObject, AVSpeechSynthesizerDelegate {
    /// Cleared before firing, so a finish followed by a cancel can't resume
    /// the same continuation twice.
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish()
    }

    private func finish() {
        let handler = onFinish
        onFinish = nil
        guard let handler else { return }
        DispatchQueue.main.async { handler() }
    }
}
