import XCTest
@testable import FlowFit

/// The conversational check-in's merge rules. These are the guardrails that
/// stop one odd model reply from corrupting the check-in, so they're tested
/// the same way the workout validator is.
final class IntakeTests: XCTestCase {
    private let allowed: [TrainingStyle] = [.calisthenics, .weightlifting, .recovery]

    private func filledCheckIn() -> DailyCheckIn {
        var checkIn = DailyCheckIn()
        checkIn.energy = .high
        checkIn.venue = .gym
        checkIn.minutesAvailable = 45
        checkIn.moodText = "great"
        checkIn.sorenessOrPain = "none"
        checkIn.preferredStyle = .weightlifting
        return checkIn
    }

    // MARK: - Merge semantics

    func testOmittedFieldsLeaveTheCheckInAlone() {
        var checkIn = filledCheckIn()
        checkIn.apply(CheckInPatch(), allowedStyles: allowed)

        XCTAssertEqual(checkIn.energy, .high)
        XCTAssertEqual(checkIn.venue, .gym)
        XCTAssertEqual(checkIn.minutesAvailable, 45)
        XCTAssertEqual(checkIn.moodText, "great")
        XCTAssertEqual(checkIn.sorenessOrPain, "none")
        XCTAssertEqual(checkIn.preferredStyle, .weightlifting)
    }

    func testProvidedFieldsOverwriteSoAClientCanCorrectThemselves() {
        var checkIn = filledCheckIn()
        checkIn.apply(
            CheckInPatch(energy: "low", venue: "home", minutesAvailable: 20),
            allowedStyles: allowed
        )

        XCTAssertEqual(checkIn.energy, .low)
        XCTAssertEqual(checkIn.venue, .home)
        XCTAssertEqual(checkIn.minutesAvailable, 20)
        // Untouched fields survive the correction.
        XCTAssertEqual(checkIn.preferredStyle, .weightlifting)
    }

    func testApplyReportsOnlyTheFieldsItAccepted() {
        var checkIn = DailyCheckIn()
        let accepted = checkIn.apply(
            CheckInPatch(energy: "low", sorenessOrPain: "calves", venue: "spaceship"),
            allowedStyles: allowed
        )

        XCTAssertEqual(accepted, [.energy, .soreness])
        // A rejected value must not be reported as known, or the coach would
        // never ask for it again.
        XCTAssertFalse(accepted.contains(.venue))
    }

    func testEmptyTextIsNotTreatedAsAnAnswer() {
        var checkIn = filledCheckIn()
        let accepted = checkIn.apply(
            CheckInPatch(moodText: "", sorenessOrPain: "   "),
            allowedStyles: allowed
        )

        XCTAssertTrue(accepted.isEmpty)
        XCTAssertEqual(checkIn.moodText, "great")
        XCTAssertEqual(checkIn.sorenessOrPain, "none")
    }

    // MARK: - Guardrails

    func testMinutesAreClampedToWhatTheFormCanShow() {
        var checkIn = DailyCheckIn()

        checkIn.apply(CheckInPatch(minutesAvailable: 600), allowedStyles: allowed)
        XCTAssertEqual(checkIn.minutesAvailable, 120)

        checkIn.apply(CheckInPatch(minutesAvailable: 1), allowedStyles: allowed)
        XCTAssertEqual(checkIn.minutesAvailable, 10)
    }

    func testDisabledStyleIsRejected() {
        var checkIn = DailyCheckIn()
        let accepted = checkIn.apply(CheckInPatch(preferredStyle: "powerlifting"), allowedStyles: allowed)

        XCTAssertTrue(accepted.isEmpty)
        XCTAssertNil(checkIn.preferredStyle, "The coach must not select a style the client disabled")
    }

    func testCoachsChoiceSentinelClearsThePreference() {
        var checkIn = filledCheckIn()
        let accepted = checkIn.apply(CheckInPatch(preferredStyle: "coach"), allowedStyles: allowed)

        XCTAssertEqual(accepted, [.style])
        XCTAssertNil(checkIn.preferredStyle)
    }

    func testUnknownEnergyIsDroppedRatherThanBreakingTheCheckIn() {
        var checkIn = filledCheckIn()
        let accepted = checkIn.apply(CheckInPatch(energy: "banana"), allowedStyles: allowed)

        XCTAssertTrue(accepted.isEmpty)
        XCTAssertEqual(checkIn.energy, .high)
    }

    func testEnergyAliasesAreTolerated() {
        XCTAssertEqual(EnergyLevel.parse("Low"), .low)
        XCTAssertEqual(EnergyLevel.parse(" exhausted "), .low)
        XCTAssertEqual(EnergyLevel.parse("moderate"), .steady)
        XCTAssertEqual(EnergyLevel.parse("energetic"), .high)
        XCTAssertNil(EnergyLevel.parse("purple"))
    }

    // MARK: - Wire format

    func testReplyDecodesWithEveryOptionalFieldAbsent() throws {
        let reply: IntakeReply = try CoachService.parse("""
        {"reply": "How are you feeling today?"}
        """)

        XCTAssertEqual(reply.reply, "How are you feeling today?")
        XCTAssertNil(reply.checkIn)
        XCTAssertFalse(reply.isReadyToGenerate, "A missing flag must read as not ready")
    }

    func testReplyDecodesAPartialPatch() throws {
        let reply: IntakeReply = try CoachService.parse("""
        {
          "reply": "Noted.",
          "checkIn": {"energy": "low", "sorenessOrPain": "calves sore"},
          "readyToGenerate": true
        }
        """)

        XCTAssertTrue(reply.isReadyToGenerate)
        XCTAssertEqual(reply.checkIn?.energy, "low")
        XCTAssertEqual(reply.checkIn?.sorenessOrPain, "calves sore")
        XCTAssertNil(reply.checkIn?.venue)
    }

    // MARK: - Mock coach

    func testMockWalksAScriptedConversationRatherThanRepeatingItself() async throws {
        let mock = MockLLMClient()
        let system = CoachService.intakeSystemPrompt(
            profile: UserProfile(
                name: "Asha",
                primaryGoal: "Rebuild strength",
                medicalNotes: "",
                injuriesOrLimitations: "",
                homeEquipment: "dumbbells",
                gymEquipment: "full gym",
                allowedStyles: allowed,
                experience: .beginner,
                daysPerWeek: 3,
                bannedMovements: [],
                intensityCeiling: .moderate
            ),
            wikiContext: "### profile\ntest",
            session: nil,
            checkIn: DailyCheckIn(),
            known: []
        )

        let opening: IntakeReply = try CoachService.parse(
            try await mock.complete(messages: [.system(system), .user("(opening)")], maxTokens: 300)
        )
        XCTAssertNil(opening.checkIn, "The greeting shouldn't claim to have learned anything")
        XCTAssertFalse(opening.isReadyToGenerate)

        let second: IntakeReply = try CoachService.parse(
            try await mock.complete(messages: [
                .system(system), .user("(opening)"), .assistant(opening.reply), .user("tired, calves sore"),
            ], maxTokens: 300)
        )
        XCTAssertEqual(second.checkIn?.energy, "low")
        XCTAssertFalse(second.isReadyToGenerate)

        let third: IntakeReply = try CoachService.parse(
            try await mock.complete(messages: [
                .system(system), .user("(opening)"), .assistant(opening.reply),
                .user("tired, calves sore"), .assistant(second.reply), .user("home, half an hour"),
            ], maxTokens: 300)
        )
        XCTAssertEqual(third.checkIn?.venue, "home")
        XCTAssertTrue(third.isReadyToGenerate, "The coach should hand over once it has enough")
    }
}
