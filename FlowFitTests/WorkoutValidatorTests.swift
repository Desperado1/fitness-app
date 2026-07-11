import XCTest
@testable import FlowFit

final class WorkoutValidatorTests: XCTestCase {
    private func makeProfile(
        styles: [TrainingStyle] = TrainingStyle.allCases,
        banned: [String] = [],
        ceiling: Intensity = .high
    ) -> UserProfile {
        UserProfile(
            name: "Test",
            allowedStyles: styles,
            bannedMovements: banned,
            intensityCeiling: ceiling
        )
    }

    private func makeWorkout(
        style: String = "weightlifting",
        intensity: String = "moderate",
        exerciseNames: [String] = ["Goblet Squat"]
    ) -> GeneratedWorkout {
        GeneratedWorkout(
            title: "Test",
            style: style,
            intensity: intensity,
            durationMinutes: 30,
            warmup: [],
            exercises: exerciseNames.map {
                PrescribedExercise(name: $0, sets: 3, reps: "10", weight: nil, restSeconds: 60, notes: nil)
            },
            cooldown: [],
            coachNote: "",
            safetyNote: ""
        )
    }

    func testClampsIntensityAboveCeiling() {
        let profile = makeProfile(ceiling: .low)
        let clamped = WorkoutValidator.clampedToCeiling(makeWorkout(intensity: "high"), profile: profile)
        XCTAssertEqual(clamped.intensity, "low")
    }

    func testLeavesIntensityAtOrBelowCeiling() {
        let profile = makeProfile(ceiling: .moderate)
        let clamped = WorkoutValidator.clampedToCeiling(makeWorkout(intensity: "low"), profile: profile)
        XCTAssertEqual(clamped.intensity, "low")
    }

    func testFlagsBannedMovementCaseInsensitive() {
        let profile = makeProfile(banned: ["Box Jump"])
        let workout = makeWorkout(exerciseNames: ["Weighted box jumps", "Goblet Squat"])
        let violations = WorkoutValidator.violations(in: workout, profile: profile)
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations[0].contains("box jumps") || violations[0].contains("Box Jump"))
    }

    func testFlagsDisabledStyle() {
        let profile = makeProfile(styles: [.calisthenics, .recovery])
        let violations = WorkoutValidator.violations(in: makeWorkout(style: "powerlifting"), profile: profile)
        XCTAssertEqual(violations.count, 1)
    }

    func testCleanWorkoutHasNoViolations() {
        let profile = makeProfile(banned: ["crunch"])
        let violations = WorkoutValidator.violations(in: makeWorkout(), profile: profile)
        XCTAssertTrue(violations.isEmpty)
    }
}
