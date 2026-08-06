import XCTest
@testable import FlowFit

/// Stands in for the microphone: the test drives transcription by hand.
/// Kept at file scope so it stays free of the test case's actor isolation,
/// exactly like the real engines.
private final class TestSpeechEngine: SpeechEngine {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?

    var isTranscribing = false
    var stopTranscribingCount = 0
    var spoken: [String] = []
    var permissionsGranted = true

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
        completion()
    }

    func stopSpeaking() {}
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

    func testAnEmptyUtteranceIsNeverSentToTheCoach() async {
        let (session, engine) = makeSession()
        var submitted: String?
        session.listen { submitted = $0 }

        // Nothing was ever heard — silence must not reach the coach as if
        // the client had said something.
        engine.onFinal?("   ")
        await settle()

        XCTAssertNil(submitted)
        XCTAssertFalse(session.isListening)
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
