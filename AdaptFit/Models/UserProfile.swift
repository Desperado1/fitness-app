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
    var equipment: String
    var allowedStyleRaws: [String]
    var experienceRaw: String
    var daysPerWeek: Int
    var createdAt: Date

    init(
        name: String = "",
        primaryGoal: String = "",
        medicalNotes: String = "",
        injuriesOrLimitations: String = "",
        equipment: String = "",
        allowedStyles: [TrainingStyle] = TrainingStyle.allCases,
        experience: ExperienceLevel = .beginner,
        daysPerWeek: Int = 3
    ) {
        self.name = name
        self.primaryGoal = primaryGoal
        self.medicalNotes = medicalNotes
        self.injuriesOrLimitations = injuriesOrLimitations
        self.equipment = equipment
        self.allowedStyleRaws = allowedStyles.map(\.rawValue)
        self.experienceRaw = experience.rawValue
        self.daysPerWeek = daysPerWeek
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
}
