import XCTest
@testable import FlowFit

/// Stands in for the microphone: the test drives transcription by hand.
/// Kept at file scope so it stays free of the test case's actor isolation,
/// exactly like the real engines.
private final class TestSpeechEngine: SpeechEngine {
    var onLevel: ((Float) -> Void)?
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?

    var isTranscribing = false
    var stopTranscribingCount = 0
    var spoken: [String] = []
    var permissionsGranted = true

    /// Off by default so most tests can `await speak` without ceremony;
    /// switched on to test what happens *during* an utterance.
    var completesSpeechImmediately = true
    var stopSpeakingCount = 0
    private var pendingSpeechCompletion: (() -> Void)?

    func requestPermissions() async -> Bool { permissionsGranted }

    func startTranscribing(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        isTranscribing = true
        self.onPartial = onPartial
        self.onFinal = onFinal
        self.onError = onError
    }

    func stopTranscribing() {
        if isTranscribing { stopTranscribingCount += 1 }
        isTranscribing = false
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        spoken.append(text)
        if completesSpeechImmediately {
            completion()
        } else {
            pendingSpeechCompletion = completion
        }
    }

    /// Mirrors the real synthesizer, whose `didCancel` runs the same
    /// completion `didFinish` would have.
    func stopSpeaking() {
        stopSpeakingCount += 1
        let completion = pendingSpeechCompletion
        pendingSpeechCompletion = nil
        completion?()
    }
}

/// Turn detection is the whole feel of voice mode — when a pause counts as
/// "done talking", and that a turn is submitted exactly once. Both are pure
/// policy in VoiceSession, so both are testable without a microphone.
@MainActor
final class VoiceSessionTests: XCTestCase {
    private func makeSession() -> (VoiceSession, TestSpeechEngine) {
        let engine = TestSpeechEngine()
        return (VoiceSession(engine: engine), engine)
    }

    /// Recognition callbacks hop to the main actor, so give the hop a turn
    /// to land before asserting on what it changed.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    func testPartialResultsUpdateTheLiveTranscript() async {
        let (session, engine) = makeSession()
        session.listen { _ in }

        engine.onPartial?("at home")
        await settle()
        XCTAssertEqual(session.partialTranscript, "at home")

        engine.onPartial?("at home for half an hour")
        await settle()
        XCTAssertEqual(session.partialTranscript, "at home for half an hour")
        XCTAssertTrue(session.isListening, "Still mid-sentence — the turn isn't over")
    }

    func testFinalResultSubmitsTheTurnAndStopsTheMicrophone() async {
        let (session, engine) = makeSession()
        var submitted: String?
        session.listen { submitted = $0 }

        engine.onFinal?("  at home, about half an hour  ")
        await settle()

        XCTAssertEqual(submitted, "at home, about half an hour", "Submitted text should be trimmed")
        XCTAssertFalse(engine.isTranscribing, "The microphone must close when the turn ends")
    }

    func testATurnIsSubmittedOnlyOnce() async {
        let (session, engine) = makeSession()
        var submissions = 0
        session.listen { _ in submissions += 1 }

        // The recognizer's final result and a late silence timer can both
        // land; the turn must still only be delivered once.
        engine.onFinal?("at home")
        engine.onFinal?("at home")
        engine.onPartial?("at home and more")
        await settle()

        XCTAssertEqual(submissions, 1)
    }

    func testAnEmptyUtteranceIsNeverSentToTheCoachAndReArmsListening() async {
        let (session, engine) = makeSession()
        var submitted: String?
        session.listen { submitted = $0 }

        // Nothing was ever heard — silence must not reach the coach as if
        // the client had said something.
        engine.onFinal?("   ")
        await settle()

        XCTAssertNil(submitted)
        // ...but the loop must not quietly die either: going idle here looks
        // exactly like a crash to someone who isn't holding the phone.
        XCTAssertTrue(session.isListening, "An empty turn should hand the microphone straight back")
        XCTAssertTrue(engine.isTranscribing)
        XCTAssertNotNil(session.notice, "The client needs to know why nothing happened")

        // And the re-armed turn still works.
        engine.onFinal?("at home")
        await settle()
        XCTAssertEqual(submitted, "at home")
    }

    func testSpeakingAgainAfterAnEmptyTurnClearsTheNotice() async {
        let (session, engine) = makeSession()
        session.listen { _ in }
        engine.onFinal?("   ")
        await settle()
        XCTAssertNotNil(session.notice)

        engine.onPartial?("at the gym")
        await settle()

        XCTAssertNil(session.notice, "Words are landing again — the hint has done its job")
    }

    func testErrorsEndTheTurnAndSurfaceAMessage() async {
        let (session, engine) = makeSession()
        session.listen { _ in }

        engine.onError?("Speech recognition isn't available right now.")
        await settle()

        XCTAssertEqual(session.errorMessage, "Speech recognition isn't available right now.")
        XCTAssertFalse(session.isListening)
        XCTAssertFalse(engine.isTranscribing)
    }

    func testStartingANewTurnClosesThePreviousOne() {
        let (session, engine) = makeSession()
        session.listen { _ in }
        session.listen { _ in }

        XCTAssertEqual(engine.stopTranscribingCount, 1, "The first turn's microphone should be closed")
        XCTAssertTrue(session.isListening)
    }

    func testStopClearsEverything() async {
        let (session, engine) = makeSession()
        session.listen { _ in }
        engine.onPartial?("half an hour")
        await settle()

        session.stop()

        XCTAssertEqual(session.partialTranscript, "")
        XCTAssertFalse(session.isListening)
        XCTAssertFalse(engine.isTranscribing)
    }

    func testRefusedPermissionsAreReported() async {
        let (session, engine) = makeSession()
        engine.permissionsGranted = false

        let granted = await session.prepare()

        XCTAssertFalse(granted)
        XCTAssertTrue(session.permissionDenied, "The caller needs this to fall back to typing")
    }

    func testSpeakingPassesTheTextThroughAndReturnsToIdle() async {
        let (session, engine) = makeSession()

        await session.speak("How are you feeling?")

        XCTAssertEqual(engine.spoken, ["How are you feeling?"])
        XCTAssertFalse(session.isListening)
    }

    // MARK: - Aliveness

    func testLevelsFollowTheEngineButAreSmoothed() async {
        let (session, engine) = makeSession()

        // A step input must not teleport: the orb glides through the gaps
        // between syllables instead of strobing.
        engine.onLevel?(1)
        await settle()
        let firstStep = session.level
        XCTAssertGreaterThan(firstStep, 0)
        XCTAssertLessThan(firstStep, 1, "A single loud buffer shouldn't snap the orb to full")

        engine.onLevel?(1)
        await settle()
        XCTAssertGreaterThan(session.level, firstStep, "Sustained sound should keep climbing")
        XCTAssertLessThanOrEqual(session.level, 1)
    }

    func testLevelReturnsToZeroWhenTheLoopStops() async {
        let (session, engine) = makeSession()
        session.listen { _ in }
        engine.onLevel?(1)
        await settle()
        XCTAssertGreaterThan(session.level, 0)

        session.stop()

        XCTAssertEqual(session.level, 0, "A stopped orb must not keep pulsing to stale audio")
    }

    func testInterruptingSpeechResolvesTheSpeakCall() async {
        let (session, engine) = makeSession()
        engine.completesSpeechImmediately = false

        // The loop awaits `speak`; being unable to cut in is exactly the
        // trapped-in-a-monologue feeling voice mode exists to avoid.
        let speaking = Task { await session.speak("Here's why we're squatting today…") }
        await settle()
        session.interruptSpeaking()
        await speaking.value

        XCTAssertEqual(engine.stopSpeakingCount, 1)
        XCTAssertEqual(session.phase, .idle, "Cutting the coach off hands the turn back")
    }

    func testThinkingFillerSpeaksWithoutClaimingToHaveAnswered() async {
        let (session, engine) = makeSession()

        await session.fillThinkingPause()

        XCTAssertEqual(engine.spoken.count, 1)
        XCTAssertTrue(ThinkingFiller.phrases.contains(engine.spoken[0]))
        XCTAssertEqual(session.phase, .thinking, "The reply hasn't landed — the orb must not say it has")
    }

    func testThinkingFillerNeverRepeatsItself() {
        var filler = ThinkingFiller()
        var previous: String?

        for _ in 0..<20 {
            let phrase = filler.next()
            XCTAssertTrue(ThinkingFiller.phrases.contains(phrase))
            XCTAssertNotEqual(phrase, previous, "A phrase heard twice running is the tell that it's canned")
            previous = phrase
        }
    }

    func testTheScriptedEngineWalksItsUtterancesInOrder() async {
        let engine = ScriptedSpeechEngine(utterances: ["first", "second"])
        var heard: [String] = []

        for _ in 0..<2 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                engine.startTranscribing(
                    onPartial: { _ in },
                    onFinal: { text in
                        heard.append(text)
                        continuation.resume()
                    },
                    onError: { _ in continuation.resume() }
                )
            }
        }

        XCTAssertEqual(heard, ["first", "second"], "CI drives the loop from this script")
    }
}
