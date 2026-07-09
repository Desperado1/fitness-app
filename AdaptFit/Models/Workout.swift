import Foundation
import SwiftData

enum WorkoutStatus: String, Codable {
    case planned, completed, skipped
}

enum Intensity: String, CaseIterable, Codable, Identifiable {
    case low, moderate, high
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
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

/// One exercise (or interval, for runs/HIIT) inside a workout.
struct ExerciseBlock: Codable, Hashable {
    var name: String
    var sets: Int
    /// Free-form so the model can say "8-10", "30 sec", or "400 m easy pace".
    var reps: String
    var restSeconds: Int
    var notes: String?
}

/// What the user told us before the workout was generated.
struct DailyCheckIn: Codable, Hashable {
    var energy: EnergyLevel = .steady
    var moodText: String = ""
    var minutesAvailable: Int = 30
    var sorenessOrPain: String = ""
    /// nil means "let the coach decide".
    var preferredStyle: TrainingStyle?
}

@Model
final class Workout {
    var date: Date
    var title: String
    var styleRaw: String
    var intensityRaw: String
    var durationMinutes: Int
    var warmup: [String]
    var blocks: [ExerciseBlock]
    var cooldown: [String]
    var coachNote: String
    var safetyNote: String
    var statusRaw: String

    // Snapshot of the check-in that produced this workout.
    var checkIn: DailyCheckIn

    // Post-workout feedback — this is what shapes the next workout.
    var feedbackRating: Int?
    var feedbackText: String?
    var completedAt: Date?

    init(date: Date, generated: GeneratedWorkout, checkIn: DailyCheckIn) {
        self.date = date
        self.title = generated.title
        self.styleRaw = generated.style
        self.intensityRaw = generated.intensity
        self.durationMinutes = generated.durationMinutes
        self.warmup = generated.warmup
        self.blocks = generated.blocks
        self.cooldown = generated.cooldown
        self.coachNote = generated.coachNote
        self.safetyNote = generated.safetyNote
        self.statusRaw = WorkoutStatus.planned.rawValue
        self.checkIn = checkIn
    }

    var style: TrainingStyle { TrainingStyle(rawValue: styleRaw) ?? .recovery }
    var intensity: Intensity { Intensity(rawValue: intensityRaw) ?? .moderate }

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
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
}

/// The JSON contract the LLM must return. Kept separate from the
/// SwiftData model so parsing failures never corrupt stored data.
struct GeneratedWorkout: Codable {
    var title: String
    var style: String
    var intensity: String
    var durationMinutes: Int
    var warmup: [String]
    var blocks: [ExerciseBlock]
    var cooldown: [String]
    var coachNote: String
    var safetyNote: String
}
