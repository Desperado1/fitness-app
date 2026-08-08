import XCTest
@testable import FlowFit

/// Canned coach: the conversation's own logic is what's under test, not the
/// network or the prompt.
private final class StubLLMClient: LLMCompleting {
    var replies: [String]
    var error: Error?
    private(set) var callCount = 0

    init(replies: [String] = [], error: Error? = nil) {
        self.replies = replies
        self.error = error
    }

    func complete(messages: [LLMMessage], maxTokens: Int) async throws -> String {
        callCount += 1
        if let error { throw error }
        guard !replies.isEmpty else { return "{}" }
        return replies[min(callCount - 1, replies.count - 1)]
    }
}

private struct StubError: LocalizedError {
    var errorDescription: String? = "The coach is unreachable."
}

/// One conversation is shared by the voice screen and the typed sheet, so
/// everything that used to live in a view — field application, the
/// ready-latch, error recovery — is policy that has to hold for both.
@MainActor
final class IntakeConversationTests: XCTestCase {
    private func makeProfile() -> UserProfile {
        UserProfile(
            name: "Asha",
            primaryGoal: "Rebuild strength",
            medicalNotes: "",
            injuriesOrLimitations: "",
            homeEquipment: "dumbbells",
            gymEquipment: "full gym",
            allowedStyles: [.calisthenics, .weightlifting, .recovery],
            experience: .beginner,
            daysPerWeek: 3,
            bannedMovements: [],
            intensityCeiling: .moderate
        )
    }

    private func makeSession() -> PlannedSession {
        PlannedSession(
            index: 0,
            focus: "Lower-body strength",
            style: "weightlifting",
            durationMinutes: 35,
            homeAlternativeNote: nil,
            exercises: []
        )
    }

    private func makeConversation(
        client: StubLLMClient,
        session: PlannedSession? = nil
    ) -> IntakeConversation {
        let conversation = IntakeConversation()
        conversation.makeCoach = { CoachService(client: client) }
        conversation.configure(profile: makeProfile(), session: session, wikiContext: { "### profile\ntest" })
        return conversation
    }

    func testTheCoachGreetsOnceAndNamesTodaysSession() {
        let conversation = makeConversation(client: StubLLMClient(), session: makeSession())

        conversation.startIfNeeded()
        conversation.startIfNeeded()

        XCTAssertEqual(conversation.transcript.count, 1, "Reopening a surface continues the conversation, not restarts it")
        XCTAssertTrue(conversation.transcript[0].content.contains("lower-body strength"))
        XCTAssertEqual(conversation.transcript[0].role, .assistant)
    }

    func testATurnAppliesWhatTheCoachHeard() async {
        let client = StubLLMClient(replies: ["""
        {
          "reply": "Gentle on those calves, then. Where are you training?",
          "checkIn": {"energy": "tired", "sorenessOrPain": "calves sore"},
          "readyToGenerate": false
        }
        """])
        let conversation = makeConversation(client: client, session: makeSession())

        let reply = await conversation.send("Pretty tired, and my calves are sore")

        XCTAssertEqual(reply, "Gentle on those calves, then. Where are you training?")
        XCTAssertEqual(conversation.checkIn.energy, .low, "\"tired\" is a near-miss the parser should take")
        XCTAssertEqual(conversation.checkIn.sorenessOrPain, "calves sore")
        XCTAssertEqual(conversation.knownFields, [.energy, .soreness])
        XCTAssertFalse(conversation.isReady, "Venue and time are still missing")
        XCTAssertEqual(conversation.transcript.map(\.role), [.user, .assistant])
    }

    func testReadinessLatchesOnceTheCoachSaysSo() async {
        let client = StubLLMClient(replies: [
            """
            {"reply": "Half an hour at home — let's go.", "checkIn": {"venue": "home", "minutesAvailable": 30}, "readyToGenerate": true}
            """,
            """
            {"reply": "Noted.", "readyToGenerate": false}
            """,
        ])
        let conversation = makeConversation(client: client)

        await conversation.send("At home, about half an hour")
        XCTAssertTrue(conversation.isReady)

        // A later turn that only adds colour must not take the hand-off away.
        await conversation.send("Oh, and my shoulder's a bit stiff")
        XCTAssertTrue(conversation.isReady, "Readiness latches")
    }

    func testReadinessAlsoFollowsFromTheFieldsThemselves() {
        let conversation = makeConversation(client: StubLLMClient())

        conversation.knownFields = [.energy, .venue]
        XCTAssertFalse(conversation.isReady)

        // Filled in by hand on the form, with the coach never saying a word.
        conversation.knownFields.insert(.minutes)
        XCTAssertTrue(conversation.isReady)
    }

    func testAFailedTurnGivesTheClientTheirWordsBack() async {
        let conversation = makeConversation(client: StubLLMClient(error: StubError()), session: makeSession())
        conversation.startIfNeeded()

        let reply = await conversation.send("At home, about half an hour")

        XCTAssertNil(reply)
        XCTAssertEqual(conversation.errorMessage, "The coach is unreachable.")
        XCTAssertEqual(
            conversation.transcript.count, 1,
            "The failed turn must come back out of the transcript, or the next call replays it as history"
        )
        XCTAssertEqual(conversation.transcript[0].role, .assistant)
    }

    func testClearingTheTranscriptResetsReadiness() async {
        let client = StubLLMClient(replies: ["""
        {"reply": "Let's go.", "readyToGenerate": true}
        """])
        let conversation = makeConversation(client: client)
        await conversation.send("Ready when you are")
        XCTAssertTrue(conversation.isReady)

        // The turns have been written into the new workout's thread —
        // tomorrow starts cold.
        conversation.clearTranscript()

        XCTAssertTrue(conversation.transcript.isEmpty)
        XCTAssertFalse(conversation.isReady)
    }
}
