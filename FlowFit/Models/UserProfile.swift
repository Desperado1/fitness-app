import Foundation
import SwiftData

/// The training styles the coach is allowed to draw from.
enum TrainingStyle: String, CaseIterable, Identifiable, Codable {
    case calisthenics
    case weightlifting
    case powerlifting
    case hiit
    case running
    case recovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calisthenics: return "Calisthenics"
        case .weightlifting: return "Weightlifting"
        case .powerlifting: return "Powerlifting"
        case .hiit: return "HIIT"
        case .running: return "Running"
        case .recovery: return "Recovery / Mobility"
        }
    }

    var symbol: String {
        switch self {
        case .calisthenics: return "figure.play"
        case .weightlifting: return "dumbbell"
        case .powerlifting: return "figure.strengthtraining.traditional"
        case .hiit: return "bolt.heart"
        case .running: return "figure.run"
        case .recovery: return "figure.cooldown"
        }
    }
}

enum ExperienceLevel: String, CaseIterable, Identifiable, Codable {
    case beginner, intermediate, advanced
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

@Model
final class UserProfile {
    var name: String
    var primaryGoal: String
    /// Free-text medical context, e.g. "10 months postpartum, PCOD, mild hypothyroidism".
    var medicalNotes: String
    var injuriesOrLimitations: String
    var homeEquipment: String
    var gymEquipment: String
    var allowedStyleRaws: [String]
    var experienceRaw: String
    var daysPerWeek: Int

    // Hard safety constraints enforced in code (WorkoutValidator), not just prompts.
    /// Movement names/keywords the coach must never program, e.g. ["box jump", "crunch"].
    var bannedMovements: [String]
    /// Generated workouts above this intensity are clamped down to it.
    var intensityCeilingRaw: String

    var createdAt: Date

    init(
        name: String = "",
        primaryGoal: String = "",
        medicalNotes: String = "",
        injuriesOrLimitations: String = "",
        homeEquipment: String = "",
        gymEquipment: String = "",
        allowedStyles: [TrainingStyle] = TrainingStyle.allCases,
        experience: ExperienceLevel = .beginner,
        daysPerWeek: Int = 3,
        bannedMovements: [String] = [],
        intensityCeiling: Intensity = .high
    ) {
        self.name = name
        self.primaryGoal = primaryGoal
        self.medicalNotes = medicalNotes
        self.injuriesOrLimitations = injuriesOrLimitations
        self.homeEquipment = homeEquipment
        self.gymEquipment = gymEquipment
        self.allowedStyleRaws = allowedStyles.map(\.rawValue)
        self.experienceRaw = experience.rawValue
        self.daysPerWeek = daysPerWeek
        self.bannedMovements = bannedMovements
        self.intensityCeilingRaw = intensityCeiling.rawValue
        self.createdAt = .now
    }

    var allowedStyles: [TrainingStyle] {
        get { allowedStyleRaws.compactMap(TrainingStyle.init(rawValue:)) }
        set { allowedStyleRaws = newValue.map(\.rawValue) }
    }

    var experience: ExperienceLevel {
        get { ExperienceLevel(rawValue: experienceRaw) ?? .beginner }
        set { experienceRaw = newValue.rawValue }
    }

    var intensityCeiling: Intensity {
        get { Intensity(rawValue: intensityCeilingRaw) ?? .high }
        set { intensityCeilingRaw = newValue.rawValue }
    }

    func equipment(at venue: Venue) -> String {
        switch venue {
        case .home: return homeEquipment
        case .gym: return gymEquipment
        }
    }
}
