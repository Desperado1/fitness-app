import Foundation

/// Builds the prompts, calls the LLM, and parses the result into a workout.
struct WorkoutGenerator {
    let client: LLMClient

    func generate(
        profile: UserProfile,
        checkIn: DailyCheckIn,
        recentWorkouts: [Workout]
    ) async throws -> GeneratedWorkout {
        let raw = try await client.complete(
            system: Self.systemPrompt,
            user: Self.userPrompt(profile: profile, checkIn: checkIn, recent: recentWorkouts)
        )
        return try Self.parse(raw)
    }

    // MARK: - Prompts

    static let systemPrompt = """
    You are a careful, encouraging personal trainer inside a workout app. \
    You design exactly ONE workout per request, personalised to the client's \
    profile, medical context, today's energy and mood, and how their recent \
    workouts felt.

    Safety rules (highest priority):
    - Always respect the client's medical notes and limitations. For \
    postpartum clients, avoid high-impact plyometrics, heavy spinal loading, \
    and crunch-style exercises unless they are clearly well past recovery; \
    prefer core rehabilitation, glute and pelvic-floor friendly work, and \
    gradual progression. For clients with PCOS/PCOD or thyroid conditions, \
    favour consistency and moderate intensity over exhaustion, and include \
    strength work which is especially beneficial for them.
    - If today's energy is low, or recent feedback was negative (soreness, \
    exhaustion, pain), reduce volume and intensity or choose a recovery \
    session. Never "push through" reported pain.
    - Only use equipment the client actually has.
    - Only choose from the training styles the client has enabled.
    - You are not a doctor: never give medical advice or diagnoses; keep the \
    safetyNote practical (form cues, when to stop).

    Programming rules:
    - Fit the workout to the minutes available, including warm-up and cool-down.
    - Vary styles and muscle groups across the week based on the recent history.
    - When recent feedback was positive and energy is good, progress slightly \
    (a little more volume, load, or a small new challenge).
    - For running or HIIT, express intervals in the blocks (e.g. name: "Brisk \
    walk / easy jog intervals", reps: "60 sec jog + 90 sec walk", sets: 8).
    - Keep language warm, plain, and brief. No emojis in exercise names.

    Output format: respond with ONLY a JSON object, no markdown fences and no \
    commentary, matching exactly this schema:
    {
      "title": "short motivating workout name",
      "style": "calisthenics|weightlifting|powerlifting|hiit|running|recovery",
      "intensity": "low|moderate|high",
      "durationMinutes": 30,
      "warmup": ["step 1", "step 2"],
      "blocks": [
        {"name": "Exercise name", "sets": 3, "reps": "8-10", "restSeconds": 60, "notes": "optional form cue"}
      ],
      "cooldown": ["step 1", "step 2"],
      "coachNote": "1-2 sentences tying today's plan to the client's mood/energy/goals",
      "safetyNote": "1-2 sentences of practical safety guidance for THIS workout"
    }
    """

    static func userPrompt(
        profile: UserProfile,
        checkIn: DailyCheckIn,
        recent: [Workout]
    ) -> String {
        let styles = profile.allowedStyles.map(\.rawValue).joined(separator: ", ")

        var lines: [String] = []
        lines.append("CLIENT PROFILE")
        lines.append("Name: \(profile.name)")
        lines.append("Primary goal: \(profile.primaryGoal)")
        lines.append("Experience: \(profile.experienceRaw)")
        lines.append("Medical notes: \(profile.medicalNotes.isEmpty ? "none reported" : profile.medicalNotes)")
        lines.append("Injuries / limitations: \(profile.injuriesOrLimitations.isEmpty ? "none reported" : profile.injuriesOrLimitations)")
        lines.append("Available equipment: \(profile.equipment.isEmpty ? "bodyweight only" : profile.equipment)")
        lines.append("Enabled training styles: \(styles)")
        lines.append("Target sessions per week: \(profile.daysPerWeek)")
        lines.append("")
        lines.append("TODAY'S CHECK-IN")
        lines.append("Energy: \(checkIn.energy.rawValue)")
        lines.append("Mood / how they feel: \(checkIn.moodText.isEmpty ? "not specified" : checkIn.moodText)")
        lines.append("Soreness or pain: \(checkIn.sorenessOrPain.isEmpty ? "none reported" : checkIn.sorenessOrPain)")
        lines.append("Time available: \(checkIn.minutesAvailable) minutes")
        if let preferred = checkIn.preferredStyle {
            lines.append("Requested style for today: \(preferred.rawValue)")
        } else {
            lines.append("Requested style for today: coach's choice")
        }
        lines.append("")
        lines.append("RECENT WORKOUTS (newest first)")
        if recent.isEmpty {
            lines.append("No workouts yet — this is the first session. Start gently.")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            for workout in recent.prefix(7) {
                var entry = "- \(formatter.string(from: workout.date)): "
                entry += "\(workout.title) [\(workout.styleRaw), \(workout.intensityRaw), \(workout.durationMinutes) min, \(workout.statusRaw)]"
                if let rating = workout.feedbackRating {
                    entry += " — felt \(rating)/5"
                }
                if let text = workout.feedbackText, !text.isEmpty {
                    entry += ": \"\(text)\""
                }
                lines.append(entry)
            }
        }
        lines.append("")
        lines.append("Design today's workout now. Return only the JSON object.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    /// Parses the model reply, tolerating markdown fences or stray prose
    /// around the JSON object.
    static func parse(_ raw: String) throws -> GeneratedWorkout {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        do {
            return try JSONDecoder().decode(GeneratedWorkout.self, from: Data(text.utf8))
        } catch {
            throw LLMError.invalidJSON(underlying: error)
        }
    }
}
