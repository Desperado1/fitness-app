import Foundation

/// Code-level safety guardrails, enforced after every generation and chat
/// edit regardless of what the prompts say. Prompts drift; these don't.
enum WorkoutValidator {
    /// Returns the workout with its intensity silently clamped to the
    /// profile's ceiling.
    static func clampedToCeiling(_ workout: GeneratedWorkout, profile: UserProfile) -> GeneratedWorkout {
        let intensity = Intensity(rawValue: workout.intensity) ?? .moderate
        guard intensity.rank > profile.intensityCeiling.rank else { return workout }
        var clamped = workout
        clamped.intensity = profile.intensityCeiling.rawValue
        return clamped
    }

    /// Hard violations that require regeneration (not silently fixable).
    static func violations(in workout: GeneratedWorkout, profile: UserProfile) -> [String] {
        var found: [String] = []

        let allowed = Set(profile.allowedStyles.map(\.rawValue))
        if !allowed.contains(workout.style) {
            found.append("Style \"\(workout.style)\" is not one of the client's enabled styles (\(allowed.sorted().joined(separator: ", "))).")
        }

        for banned in profile.bannedMovements {
            let term = banned.trimmingCharacters(in: .whitespaces).lowercased()
            guard !term.isEmpty else { continue }
            for exercise in workout.exercises where exercise.name.lowercased().contains(term) {
                found.append("Exercise \"\(exercise.name)\" matches the banned movement \"\(banned)\".")
            }
        }

        return found
    }
}

enum CoachError: LocalizedError {
    case unsafeWorkout(violations: [String])

    var errorDescription: String? {
        switch self {
        case .unsafeWorkout(let violations):
            return "The generated workout broke safety constraints and couldn't be fixed automatically:\n" +
                violations.map { "• \($0)" }.joined(separator: "\n")
        }
    }
}
