import XCTest
@testable import FlowFit

final class ModelTests: XCTestCase {
    private func makeGenerated(exerciseNames: [String]) -> GeneratedWorkout {
        GeneratedWorkout(
            title: "Test",
            style: "calisthenics",
            intensity: "moderate",
            durationMinutes: 30,
            warmup: ["walk"],
            exercises: exerciseNames.map {
                PrescribedExercise(name: $0, sets: 3, reps: "10", weight: nil, restSeconds: 60, notes: nil)
            },
            cooldown: ["stretch"],
            coachNote: "note",
            safetyNote: "safety"
        )
    }

    func testExerciseResultPerformedSummaries() {
        var result = ExerciseResult(prescribed: PrescribedExercise(
            name: "Goblet Squat", sets: 3, reps: "8-10", weight: "12 kg", restSeconds: 90, notes: nil
        ))
        XCTAssertEqual(result.performedSummary, "Goblet Squat: 3×8-10 @ 12 kg — as prescribed")

        result.status = .adjusted
        result.actualWeight = "10 kg"
        XCTAssertEqual(result.performedSummary, "Goblet Squat: prescribed 3×8-10 @ 12 kg, did 3×8-10 @ 10 kg")

        result.status = .skipped
        result.resultNote = "knee pain"
        XCTAssertEqual(result.performedSummary, "Goblet Squat: 3×8-10 @ 12 kg — skipped (knee pain)")
    }

    func testApplyPreservesActualsForKeptExercises() {
        let workout = Workout(date: .now, generated: makeGenerated(exerciseNames: ["Push-up", "Squat"]), checkIn: DailyCheckIn())
        workout.exercises[1].status = .adjusted
        workout.exercises[1].actualReps = "8"

        // Coach edit swaps Push-up for Band Row, keeps Squat.
        workout.apply(makeGenerated(exerciseNames: ["Band Row", "Squat"]))

        XCTAssertEqual(workout.exercises.map(\.name), ["Band Row", "Squat"])
        XCTAssertEqual(workout.exercises[0].status, .asPrescribed)
        XCTAssertEqual(workout.exercises[1].status, .adjusted)
        XCTAssertEqual(workout.exercises[1].actualReps, "8")
    }

    func testBlockSessionCompletionAndSummary() {
        let generated = GeneratedBlock(
            rationale: "Easy start.",
            sessions: [
                GeneratedBlock.Session(focus: "Strength", style: "weightlifting", durationMinutes: 40, homeAlternativeNote: nil, exercises: []),
                GeneratedBlock.Session(focus: "Recovery", style: "recovery", durationMinutes: 20, homeAlternativeNote: nil, exercises: []),
            ]
        )
        let block = TrainingBlock(startDate: .now, generated: generated)
        XCTAssertEqual(block.nextPendingSession?.index, 0)

        block.markSessionCompleted(0)
        XCTAssertEqual(block.nextPendingSession?.index, 1)
        XCTAssertEqual(block.status, .active)

        block.markSessionCompleted(1)
        XCTAssertNil(block.nextPendingSession)
        XCTAssertEqual(block.status, .completed)
        XCTAssertTrue(block.summary.contains("2/2 sessions done"))
    }

    func testSkippedSessionAdvancesPlan() {
        func session(_ focus: String) -> GeneratedBlock.Session {
            GeneratedBlock.Session(focus: focus, style: "recovery", durationMinutes: 20, homeAlternativeNote: nil, exercises: [])
        }
        let generated = GeneratedBlock(
            rationale: "Mixed week.",
            sessions: [session("Strength"), session("Recovery"), session("Cardio")]
        )
        let block = TrainingBlock(startDate: .now, generated: generated)

        // Skipping the first session advances to the next, block stays active.
        block.markSessionSkipped(0)
        XCTAssertEqual(block.nextPendingSession?.index, 1)
        XCTAssertEqual(block.status, .active)
        XCTAssertEqual(block.resolvedSessionCount, 1)

        block.markSessionCompleted(1)
        XCTAssertEqual(block.nextPendingSession?.index, 2)

        // Every session resolved (1 done, 2 skipped) → week is over.
        block.markSessionSkipped(2)
        XCTAssertNil(block.nextPendingSession)
        XCTAssertEqual(block.status, .completed)

        // Summary distinguishes done from skipped for the next planner.
        XCTAssertTrue(block.summary.contains("1/3 sessions done"))
        XCTAssertTrue(block.summary.contains("2 skipped"))
        XCTAssertTrue(block.summary.contains("✗ skipped"))
    }

    func testCompletingASkippedSessionOverridesSkip() {
        let generated = GeneratedBlock(
            rationale: "x",
            sessions: [GeneratedBlock.Session(focus: "Strength", style: "weightlifting", durationMinutes: 40, homeAlternativeNote: nil, exercises: [])]
        )
        let block = TrainingBlock(startDate: .now, generated: generated)
        block.markSessionSkipped(0)
        block.markSessionCompleted(0)
        XCTAssertEqual(block.completedSessionIndices, [0])
        XCTAssertFalse(block.skippedSessionIndices.contains(0))
        XCTAssertEqual(block.resolvedSessionCount, 1)
    }

    func testHistoryLineIncludesFeedback() {
        let workout = Workout(date: .now, generated: makeGenerated(exerciseNames: ["Squat"]), checkIn: DailyCheckIn())
        workout.status = .completed
        workout.feedbackRating = 5
        workout.feedbackText = "great"
        XCTAssertTrue(workout.historyLine.contains("felt 5/5: great"))
        XCTAssertTrue(workout.historyLine.contains("calisthenics"))
    }
}
