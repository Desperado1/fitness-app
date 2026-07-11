import XCTest
@testable import FlowFit

final class ParsingTests: XCTestCase {
    private let workoutJSON = """
    {
      "title": "Steady Strength",
      "style": "weightlifting",
      "intensity": "moderate",
      "durationMinutes": 40,
      "warmup": ["5 min brisk walk", "Arm circles"],
      "exercises": [
        {"name": "Goblet Squat", "sets": 3, "reps": "8-10", "weight": "12 kg", "restSeconds": 90, "notes": "Chest tall"},
        {"name": "Incline Push-up", "sets": 3, "reps": "10", "weight": null, "restSeconds": 60, "notes": null}
      ],
      "cooldown": ["Hamstring stretch"],
      "coachNote": "Solid energy today, so we build.",
      "safetyNote": "Stop if anything pinches."
    }
    """

    func testParsesCleanWorkoutJSON() throws {
        let workout: GeneratedWorkout = try CoachService.parse(workoutJSON)
        XCTAssertEqual(workout.title, "Steady Strength")
        XCTAssertEqual(workout.exercises.count, 2)
        XCTAssertEqual(workout.exercises[0].weight, "12 kg")
        XCTAssertNil(workout.exercises[1].weight)
    }

    func testParsesFencedJSON() throws {
        let fenced = "```json\n\(workoutJSON)\n```"
        let workout: GeneratedWorkout = try CoachService.parse(fenced)
        XCTAssertEqual(workout.style, "weightlifting")
    }

    func testParsesJSONWithSurroundingProse() throws {
        let noisy = "Here is your workout:\n\(workoutJSON)\nEnjoy!"
        let workout: GeneratedWorkout = try CoachService.parse(noisy)
        XCTAssertEqual(workout.durationMinutes, 40)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try CoachService.parse("not json at all") as GeneratedWorkout)
    }

    func testParsesGeneratedBlock() throws {
        let json = """
        {
          "rationale": "Two strength days and one easy day to rebuild consistency.",
          "sessions": [
            {
              "focus": "Lower-body strength",
              "style": "weightlifting",
              "durationMinutes": 40,
              "homeAlternativeNote": "Use the single dumbbell for goblet variations.",
              "exercises": [
                {"name": "Goblet Squat", "sets": 3, "reps": "8-10", "weight": "12 kg", "restSeconds": 90, "notes": null}
              ]
            },
            {
              "focus": "Easy intervals",
              "style": "running",
              "durationMinutes": 25,
              "homeAlternativeNote": null,
              "exercises": [
                {"name": "Jog/walk intervals", "sets": 6, "reps": "60 sec jog + 90 sec walk", "weight": null, "restSeconds": 0, "notes": null}
              ]
            }
          ]
        }
        """
        let block: GeneratedBlock = try CoachService.parse(json)
        XCTAssertEqual(block.sessions.count, 2)
        XCTAssertEqual(block.sessions[1].style, "running")
    }

    func testChatReplyWithoutEdit() throws {
        let json = """
        {"reply": "Deadlifts build your posterior chain safely at this load.", "updatedWorkout": null}
        """
        let reply: ChatCoachReply = try CoachService.parse(json)
        XCTAssertNil(reply.updatedWorkout)
        XCTAssertFalse(reply.reply.isEmpty)
    }

    func testChatReplyWithEdit() throws {
        let json = """
        {"reply": "Swapped push-ups for band rows to spare your wrists.", "updatedWorkout": \(workoutJSON)}
        """
        let reply: ChatCoachReply = try CoachService.parse(json)
        XCTAssertEqual(reply.updatedWorkout?.title, "Steady Strength")
    }

    func testWikiUpdates() throws {
        let json = """
        {"pages": {"log": "# Coach's Log\\n- 2026-07-10: Solid session, felt 4/5", "progressions": "# Progressions\\n- Goblet squat: 3x10 @ 12 kg"}}
        """
        let updates: WikiUpdates = try CoachService.parse(json)
        XCTAssertEqual(updates.pages.count, 2)
        XCTAssertNotNil(updates.pages["log"])
    }
}
