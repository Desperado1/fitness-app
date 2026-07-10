import Foundation
import SwiftData

enum WorkoutStatus: String, Codable {
    case planned, completed, skipped
}

enum Intensity: String, CaseIterable, Codable, Identifiable {
    case low, moderate, high
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Ordering used to clamp against the profile's intensity ceiling.
    var rank: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        }
    }
}

enum Venue: String, CaseIterable, Codable, Identifiable {
    case home, gym
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .gym: return "building.2"
        }
    }
}

enum EnergyLevel: String, CaseIterable, Codable, Identifiable {
    case low, steady, high
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Running on empty"
        case .steady: return "Steady"
        case .high: return "Full of energy"
        }
    }

    var emoji: String {
        switch self {
        case .low: return "🪫"
        case .steady: return "🙂"
        case .high: return "⚡️"
        }
    }
}

/// How the user actually performed one prescribed exercise.
enum ExerciseStatus: String, Codable {
    case asPrescribed, adjusted, skipped
}

/// One exercise in a workout: the prescription plus what was actually done.
/// Defaults to "as prescribed" so logging is only needed when something changed.
struct ExerciseResult: Codable, Hashable, Identifiable {
    var id: UUID = UUID()

    // Prescription (from the LLM).
    var name: String
    var prescribedSets: Int
    /// Free-form so the coach can say "8-10", "30 sec", or "400 m easy pace".
    var prescribedReps: String
    /// e.g. "12 kg", "bodyweight", "light band". nil for runs/stretches.
    var prescribedWeight: String?
    var restSeconds: Int
    var notes: String?

    // Actuals (from the user; nil means "as prescribed").
    var statusRaw: String = ExerciseStatus.asPrescribed.rawValue
    var actualSets: Int?
    var actualReps: String?
    var actualWeight: String?
    var resultNote: String?

    var status: ExerciseStatus {
        get { ExerciseStatus(rawValue: statusRaw) ?? .asPrescribed }
        set { statusRaw = newValue.rawValue }
    }

    /// One-line summary of what was done, for prompts and the wiki scribe.
    var performedSummary: String {
        let prescription = "\(prescribedSets)×\(prescribedReps)\(prescribedWeight.map { " @ \($0)" } ?? "")"
        switch status {
        case .asPrescribed:
            return "\(name): \(prescription) — as prescribed"
        case .skipped:
            return "\(name): \(prescription) — skipped\(resultNote.map { " (\($0))" } ?? "")"
        case .adjusted:
            let sets = actualSets ?? prescribedSets
            let reps = actualReps ?? prescribedReps
            let weight = actualWeight ?? prescribedWeight
            let done = "\(sets)×\(reps)\(weight.map { " @ \($0)" } ?? "")"
            return "\(name): prescribed \(prescription), did \(done)\(resultNote.map { " (\($0))" } ?? "")"
        }
    }

    init(prescribed: PrescribedExercise) {
        self.name = prescribed.name
        self.prescribedSets = prescribed.sets
        self.prescribedReps = prescribed.reps
        self.prescribedWeight = prescribed.weight
        self.restSeconds = prescribed.restSeconds
        self.notes = prescribed.notes
    }
}

/// What the user told us before the workout was generated.
struct DailyCheckIn: Codable, Hashable {
    var energy: EnergyLevel = .steady
    var moodText: String = ""
    var minutesAvailable: Int = 30
    var sorenessOrPain: String = ""
    var venue: Venue = .home
    /// nil means "let the coach decide".
    var preferredStyle: TrainingStyle?
}

@Model
final class Workout {
    /// Stable key used to relate chat messages to this workout.
    var uuid: UUID
    var date: Date
    var title: String
    var styleRaw: String
    var intensityRaw: String
    var durationMinutes: Int
    var warmup: [String]
    var exercises: [ExerciseResult]
    var cooldown: [String]
    var coachNote: String
    var safetyNote: String
    var statusRaw: String

    /// Which planned session of the active block this realizes; nil for one-off workouts.
    var blockSessionIndex: Int?

    // Snapshot of the check-in that produced this workout (includes venue).
    var checkIn: DailyCheckIn

    // Post-workout data — feeds the scribe and the next plan.
    var actualDurationMinutes: Int?
    var feedbackRating: Int?
    var feedbackText: String?
    var completedAt: Date?

    init(date: Date, generated: GeneratedWorkout, checkIn: DailyCheckIn, blockSessionIndex: Int? = nil) {
        self.uuid = UUID()
        self.date = date
        self.title = generated.title
        self.styleRaw = generated.style
        self.intensityRaw = generated.intensity
        self.durationMinutes = generated.durationMinutes
        self.warmup = generated.warmup
        self.exercises = generated.exercises.map(ExerciseResult.init(prescribed:))
        self.cooldown = generated.cooldown
        self.coachNote = generated.coachNote
        self.safetyNote = generated.safetyNote
        self.statusRaw = WorkoutStatus.planned.rawValue
        self.blockSessionIndex = blockSessionIndex
        self.checkIn = checkIn
    }

    var style: TrainingStyle { TrainingStyle(rawValue: styleRaw) ?? .recovery }
    var intensity: Intensity { Intensity(rawValue: intensityRaw) ?? .moderate }
    var venue: Venue { checkIn.venue }

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    /// Replaces the prescription with a coach edit (from chat), preserving
    /// any actuals the user already logged for exercises that kept their name.
    func apply(_ generated: GeneratedWorkout) {
        let previous = Dictionary(grouping: exercises, by: \.name)
        title = generated.title
        styleRaw = generated.style
        intensityRaw = generated.intensity
        durationMinutes = generated.durationMinutes
        warmup = generated.warmup
        cooldown = generated.cooldown
        coachNote = generated.coachNote
        safetyNote = generated.safetyNote
        exercises = generated.exercises.map { prescribed in
            var result = ExerciseResult(prescribed: prescribed)
            if let old = previous[prescribed.name]?.first, old.status != .asPrescribed {
                result.statusRaw = old.statusRaw
                result.actualSets = old.actualSets
                result.actualReps = old.actualReps
                result.actualWeight = old.actualWeight
                result.resultNote = old.resultNote
            }
            return result
        }
    }

    var feedbackEmoji: String? {
        guard let rating = feedbackRating else { return nil }
        switch rating {
        case ...1: return "😣"
        case 2: return "😕"
        case 3: return "😌"
        case 4: return "😊"
        default: return "🤩"
        }
    }

    /// Compact one-line record used for scribe prompts and wiki rebuilds.
    var historyLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var line = "\(formatter.string(from: date)) | \(title) | \(styleRaw), \(intensityRaw), \(venue.rawValue), \(actualDurationMinutes ?? durationMinutes) min | \(statusRaw)"
        if let rating = feedbackRating { line += " | felt \(rating)/5" }
        if let text = feedbackText, !text.isEmpty { line += ": \(text)" }
        return line
    }
}

// MARK: - LLM JSON contracts

/// One prescribed exercise as the LLM emits it (also used inside planned sessions).
struct PrescribedExercise: Codable, Hashable {
    var name: String
    var sets: Int
    var reps: String
    var weight: String?
    var restSeconds: Int
    var notes: String?
}

/// The JSON contract for a concrete workout. Kept separate from the
/// SwiftData model so parsing failures never corrupt stored data.
struct GeneratedWorkout: Codable {
    var title: String
    var style: String
    var intensity: String
    var durationMinutes: Int
    var warmup: [String]
    var exercises: [PrescribedExercise]
    var cooldown: [String]
    var coachNote: String
    var safetyNote: String
}
