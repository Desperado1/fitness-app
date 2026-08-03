import Foundation

/// The intake coach's structured reply: something to say, whatever it
/// learned about today, and whether it has enough to build the workout.
struct IntakeReply: Codable {
    var reply: String
    /// Optional so a turn that learns nothing new still decodes.
    var checkIn: CheckInPatch?
    /// Optional so an omitted flag reads as "not ready" rather than failing.
    var readyToGenerate: Bool?

    var isReadyToGenerate: Bool { readyToGenerate ?? false }
}

/// An all-optional mirror of `DailyCheckIn`, used only as the intake wire
/// format. `DailyCheckIn` gives `venue` and `minutesAvailable` non-optional
/// defaults, so decoding a partial reply straight into it would either fail
/// or silently reset fields an earlier turn had established.
///
/// nil means "didn't learn this yet" — never "clear it".
struct CheckInPatch: Codable {
    var energy: String?
    var moodText: String?
    var sorenessOrPain: String?
    var venue: String?
    var minutesAvailable: Int?
    var preferredStyle: String?
}

/// One line of the intake conversation.
///
/// Not a `CoachChatMessage`, because intake happens *before* today's workout
/// exists and there is no `workoutUUID` to key it by yet. Once the workout is
/// created these turns are written into its thread, so the chat coach picks up
/// mid-conversation instead of starting cold.
struct IntakeTurn: Identifiable, Hashable {
    let id = UUID()
    let role: ChatRole
    let content: String
}

/// The fields the intake conversation is trying to fill.
///
/// `DailyCheckIn` gives every field a usable default, so its values alone
/// can't tell "the client said 30 minutes" from "nobody has mentioned time".
/// Tracking which fields are actually established is what stops the coach
/// re-asking — and what lets it know when it has enough to build.
enum CheckInField: String, CaseIterable {
    case energy, mood, soreness, venue, minutes, style

    /// The fields worth having before generating. Mood and soreness are
    /// colour: welcome, never worth an extra round of questions.
    static let required: [CheckInField] = [.energy, .venue, .minutes]
}

extension DailyCheckIn {
    /// Minutes the check-in UI can represent (matches TodayView's stepper),
    /// so a value the coach sets is always visible and adjustable.
    static let minutesRange = 10...120

    /// Values that mean "no style preference — coach decides". Needed because
    /// nil already means "didn't ask yet"; without a sentinel there would be
    /// no way for the client to actively hand the choice back to the coach.
    static let coachsChoiceValues: Set<String> = ["coach", "coachs choice", "coach's choice", "any", "none", "null"]

    /// Merges one intake turn: non-nil fields overwrite, nil leaves the
    /// current value alone, so a later turn can correct an earlier one
    /// without a reply that stays quiet wiping what is already known.
    ///
    /// Values the app can't honour are dropped rather than thrown — the same
    /// "code decides, not the prompt" stance as `WorkoutValidator`. One odd
    /// model reply must never break the check-in.
    ///
    /// Returns the fields it actually accepted, so the caller can track what
    /// the conversation has established (see `CheckInField`). A dropped value
    /// is deliberately not reported as known: the coach should ask again.
    @discardableResult
    mutating func apply(_ patch: CheckInPatch, allowedStyles: [TrainingStyle]) -> Set<CheckInField> {
        var accepted: Set<CheckInField> = []

        if let energy = patch.energy.flatMap(EnergyLevel.parse) {
            self.energy = energy
            accepted.insert(.energy)
        }
        if let mood = patch.moodText?.trimmed, !mood.isEmpty {
            moodText = mood
            accepted.insert(.mood)
        }
        if let soreness = patch.sorenessOrPain?.trimmed, !soreness.isEmpty {
            sorenessOrPain = soreness
            accepted.insert(.soreness)
        }
        if let venue = patch.venue?.trimmed.lowercased(), let parsed = Venue(rawValue: venue) {
            self.venue = parsed
            accepted.insert(.venue)
        }
        if let minutes = patch.minutesAvailable {
            minutesAvailable = min(max(minutes, Self.minutesRange.lowerBound), Self.minutesRange.upperBound)
            accepted.insert(.minutes)
        }
        if let styleRaw = patch.preferredStyle?.trimmed.lowercased(), !styleRaw.isEmpty {
            if Self.coachsChoiceValues.contains(styleRaw) {
                preferredStyle = nil
                accepted.insert(.style)
            } else if let style = TrainingStyle(rawValue: styleRaw), allowedStyles.contains(style) {
                // A style the user disabled is never selectable by the coach,
                // exactly as a banned movement is never programmable.
                preferredStyle = style
                accepted.insert(.style)
            }
        }
        return accepted
    }
}

extension EnergyLevel {
    /// Tolerates the near-misses a model reaches for ("tired", "moderate")
    /// instead of discarding an otherwise good turn.
    static func parse(_ raw: String) -> EnergyLevel? {
        let value = raw.trimmed.lowercased()
        if let exact = EnergyLevel(rawValue: value) { return exact }
        switch value {
        case "tired", "exhausted", "drained", "empty", "flat": return .low
        case "medium", "moderate", "ok", "okay", "normal", "fine": return .steady
        case "great", "energetic", "good", "strong", "full": return .high
        default: return nil
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
