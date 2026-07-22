import XCTest
@testable import FlowFit

final class PromptBuilderTests: XCTestCase {
    private func makeProfile() -> UserProfile {
        UserProfile(
            name: "Asha",
            primaryGoal: "Rebuild strength",
            medicalNotes: "10 months postpartum, PCOD, mild thyroid issue",
            injuriesOrLimitations: "",
            homeEquipment: "pair of dumbbells, resistance band",
            gymEquipment: "full gym",
            allowedStyles: [.calisthenics, .weightlifting, .recovery],
            experience: .beginner,
            daysPerWeek: 3,
            bannedMovements: ["box jump"],
            intensityCeiling: .moderate
        )
    }

    func testModulatorPromptCarriesCheckInAndConstraints() {
        var checkIn = DailyCheckIn()
        checkIn.energy = .low
        checkIn.venue = .home
        checkIn.minutesAvailable = 25
        checkIn.sorenessOrPain = "lower back tight"

        let prompt = CoachService.modulatorUserPrompt(
            profile: makeProfile(),
            wikiContext: "### profile\ntest wiki",
            session: nil,
            checkIn: checkIn
        )

        XCTAssertTrue(prompt.contains("Energy: low"))
        XCTAssertTrue(prompt.contains("Venue: home"))
        XCTAssertTrue(prompt.contains("25 minutes"))
        XCTAssertTrue(prompt.contains("lower back tight"))
        XCTAssertTrue(prompt.contains("box jump"))
        XCTAssertTrue(prompt.contains("Maximum intensity: moderate"))
        XCTAssertTrue(prompt.contains("test wiki"))
        XCTAssertTrue(prompt.contains("standalone workout"))
    }

    func testModulatorPromptIncludesPlannedSession() {
        let session = PlannedSession(
            index: 1,
            focus: "Lower-body strength",
            style: "weightlifting",
            durationMinutes: 40,
            homeAlternativeNote: "Goblet variations with the dumbbell.",
            exercises: [
                PrescribedExercise(name: "Goblet Squat", sets: 3, reps: "8-10", weight: "12 kg", restSeconds: 90, notes: nil)
            ]
        )
        let prompt = CoachService.modulatorUserPrompt(
            profile: makeProfile(),
            wikiContext: "",
            session: session,
            checkIn: DailyCheckIn()
        )
        XCTAssertTrue(prompt.contains("Lower-body strength"))
        XCTAssertTrue(prompt.contains("Goblet Squat: 3×8-10 @ 12 kg"))
        XCTAssertTrue(prompt.contains("Goblet variations"))
    }

    func testModulatorPromptRequestsAlternativeWhenAvoiding() {
        let previous = GeneratedWorkout(
            title: "Steady Strength",
            style: "weightlifting",
            intensity: "moderate",
            durationMinutes: 30,
            warmup: [],
            exercises: [
                PrescribedExercise(name: "Goblet Squat", sets: 3, reps: "8-10", weight: "12 kg", restSeconds: 90, notes: nil),
                PrescribedExercise(name: "Glute Bridge", sets: 3, reps: "12", weight: nil, restSeconds: 60, notes: nil),
            ],
            cooldown: [],
            coachNote: "",
            safetyNote: ""
        )
        let prompt = CoachService.modulatorUserPrompt(
            profile: makeProfile(),
            wikiContext: "",
            session: nil,
            checkIn: DailyCheckIn(),
            avoiding: previous
        )
        XCTAssertTrue(prompt.contains("DIFFERENT ALTERNATIVE"))
        XCTAssertTrue(prompt.contains("Steady Strength"))
        XCTAssertTrue(prompt.contains("Goblet Squat"))
        XCTAssertTrue(prompt.contains("Glute Bridge"))
    }

    func testModulatorPromptOmitsAlternativeSectionByDefault() {
        let prompt = CoachService.modulatorUserPrompt(
            profile: makeProfile(),
            wikiContext: "",
            session: nil,
            checkIn: DailyCheckIn()
        )
        XCTAssertFalse(prompt.contains("DIFFERENT ALTERNATIVE"))
    }

    func testPlannerPromptStatesSessionCountAndHistory() {
        let prompt = CoachService.plannerUserPrompt(
            profile: makeProfile(),
            wikiContext: "### progressions\nGoblet squat 3x10 @ 12 kg",
            lastBlockSummary: "Week of Jul 1 (completed, 3/3 sessions done)"
        )
        XCTAssertTrue(prompt.contains("exactly 3 sessions"))
        XCTAssertTrue(prompt.contains("Week of Jul 1"))
        XCTAssertTrue(prompt.contains("Goblet squat 3x10 @ 12 kg"))
    }

    func testScribePromptCarriesActualsAndFeedback() {
        var checkIn = DailyCheckIn()
        checkIn.venue = .gym
        let generated = GeneratedWorkout(
            title: "Steady Strength",
            style: "weightlifting",
            intensity: "moderate",
            durationMinutes: 40,
            warmup: [],
            exercises: [
                PrescribedExercise(name: "Goblet Squat", sets: 3, reps: "8-10", weight: "12 kg", restSeconds: 90, notes: nil),
                PrescribedExercise(name: "Incline Push-up", sets: 3, reps: "10", weight: nil, restSeconds: 60, notes: nil),
            ],
            cooldown: [],
            coachNote: "",
            safetyNote: ""
        )
        let workout = Workout(date: .now, generated: generated, checkIn: checkIn)
        workout.exercises[0].status = .adjusted
        workout.exercises[0].actualWeight = "10 kg"
        workout.feedbackRating = 4
        workout.feedbackText = "Felt strong"
        workout.actualDurationMinutes = 35

        let prompt = CoachService.scribeUserPrompt(wikiContext: "### log\n", workout: workout)
        XCTAssertTrue(prompt.contains("did 3×8-10 @ 10 kg"))
        XCTAssertTrue(prompt.contains("Incline Push-up: 3×10 — as prescribed"))
        XCTAssertTrue(prompt.contains("4/5"))
        XCTAssertTrue(prompt.contains("Felt strong"))
        XCTAssertTrue(prompt.contains("Actual duration: 35 minutes"))
    }
}
