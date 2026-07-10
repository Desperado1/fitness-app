import Foundation

/// The chat coach's structured reply: a message, plus optionally a full
/// replacement prescription for today's workout.
struct ChatCoachReply: Codable {
    var reply: String
    var updatedWorkout: GeneratedWorkout?
}

/// Scribe/rebuild reply: wiki pages to overwrite, keyed by slug.
struct WikiUpdates: Codable {
    var pages: [String: String]
}

/// All LLM roles: weekly Planner, daily Modulator, Chat coach, wiki Scribe,
/// and wiki Rebuild. Prompt builders are static and pure for testability.
struct CoachService {
    let client: any LLMCompleting

    /// The coach as configured in Settings (or the mock under -mock-llm).
    static func fromSettings() -> CoachService {
        CoachService(client: makeLLMClient())
    }

    // MARK: - Planner

    func planBlock(
        profile: UserProfile,
        wikiContext: String,
        lastBlockSummary: String?
    ) async throws -> GeneratedBlock {
        let raw = try await client.complete(
            system: Self.plannerSystemPrompt,
            user: Self.plannerUserPrompt(profile: profile, wikiContext: wikiContext, lastBlockSummary: lastBlockSummary)
        )
        return try Self.parse(raw)
    }

    // MARK: - Modulator

    /// Turns today's planned session (or nothing, for a one-off quick
    /// workout) into a concrete workout. Applies code-level guardrails,
    /// retrying once with the violations fed back before giving up.
    func generateWorkout(
        profile: UserProfile,
        wikiContext: String,
        session: PlannedSession?,
        checkIn: DailyCheckIn
    ) async throws -> GeneratedWorkout {
        var messages: [LLMMessage] = [
            .system(Self.modulatorSystemPrompt),
            .user(Self.modulatorUserPrompt(profile: profile, wikiContext: wikiContext, session: session, checkIn: checkIn)),
        ]

        let firstRaw = try await client.complete(messages: messages)
        var workout: GeneratedWorkout = try Self.parse(firstRaw)
        workout = WorkoutValidator.clampedToCeiling(workout, profile: profile)

        var violations = WorkoutValidator.violations(in: workout, profile: profile)
        guard !violations.isEmpty else { return workout }

        messages.append(.assistant(firstRaw))
        messages.append(.user("""
        The workout you produced violates hard safety constraints:
        \(violations.map { "- \($0)" }.joined(separator: "\n"))
        Regenerate the full workout JSON with these problems fixed. Same schema, JSON only.
        """))
        let retryRaw = try await client.complete(messages: messages)
        workout = try Self.parse(retryRaw)
        workout = WorkoutValidator.clampedToCeiling(workout, profile: profile)

        violations = WorkoutValidator.violations(in: workout, profile: profile)
        guard violations.isEmpty else {
            throw CoachError.unsafeWorkout(violations: violations)
        }
        return workout
    }

    // MARK: - Chat

    func chat(
        profile: UserProfile,
        wikiContext: String,
        workout: Workout,
        history: [CoachChatMessage],
        userMessage: String
    ) async throws -> ChatCoachReply {
        var messages: [LLMMessage] = [
            .system(Self.chatSystemPrompt(profile: profile, wikiContext: wikiContext, workout: workout)),
        ]
        for message in history {
            messages.append(LLMMessage(role: message.role.rawValue, content: message.content))
        }
        messages.append(.user(userMessage))

        let raw = try await client.complete(messages: messages)
        var reply: ChatCoachReply = try Self.parse(raw)

        if var updated = reply.updatedWorkout {
            updated = WorkoutValidator.clampedToCeiling(updated, profile: profile)
            let violations = WorkoutValidator.violations(in: updated, profile: profile)
            if violations.isEmpty {
                reply.updatedWorkout = updated
            } else {
                // Refuse the unsafe edit but keep the conversation useful.
                reply.updatedWorkout = nil
                reply.reply += "\n\n(I tried to change the workout but the change broke a safety rule, so I left it as is.)"
            }
        }
        return reply
    }

    // MARK: - Scribe

    /// Called after a workout is completed: returns wiki page updates.
    func scribeUpdates(
        wikiContext: String,
        workout: Workout
    ) async throws -> [String: String] {
        let raw = try await client.complete(
            system: Self.scribeSystemPrompt,
            user: Self.scribeUserPrompt(wikiContext: wikiContext, workout: workout)
        )
        let updates: WikiUpdates = try Self.parse(raw)
        return updates.pages
    }

    // MARK: - Rebuild

    /// Regenerates the whole wiki from the raw history — the escape hatch
    /// when the wiki has drifted or bloated.
    func rebuildWiki(
        profile: UserProfile,
        historyLines: [String]
    ) async throws -> [String: String] {
        let raw = try await client.complete(
            system: Self.rebuildSystemPrompt,
            user: Self.rebuildUserPrompt(profile: profile, historyLines: historyLines),
            maxTokens: 8192
        )
        let updates: WikiUpdates = try Self.parse(raw)
        return updates.pages
    }

    // MARK: - Shared prompt pieces

    static let safetyRules = """
    You are a careful, encouraging personal trainer inside a workout app.

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
    - Never program any movement on the banned list.
    - Only use equipment available at the client's venue today.
    - Only choose from the training styles the client has enabled.
    - You are not a doctor: never give medical advice or diagnoses.
    """

    static let workoutJSONSchema = """
    {
      "title": "short motivating workout name",
      "style": "calisthenics|weightlifting|powerlifting|hiit|running|recovery",
      "intensity": "low|moderate|high",
      "durationMinutes": 30,
      "warmup": ["step 1", "step 2"],
      "exercises": [
        {"name": "Exercise name", "sets": 3, "reps": "8-10", "weight": "12 kg dumbbells or null for bodyweight", "restSeconds": 60, "notes": "optional form cue"}
      ],
      "cooldown": ["step 1", "step 2"],
      "coachNote": "1-2 sentences tying today's plan to the client's mood/energy/goals",
      "safetyNote": "1-2 sentences of practical safety guidance for THIS workout"
    }
    """

    static func profileConstraints(_ profile: UserProfile) -> String {
        """
        HARD CONSTRAINTS (from the app, authoritative)
        Enabled styles: \(profile.allowedStyles.map(\.rawValue).joined(separator: ", "))
        Banned movements: \(profile.bannedMovements.isEmpty ? "none" : profile.bannedMovements.joined(separator: ", "))
        Maximum intensity: \(profile.intensityCeilingRaw)
        Home equipment: \(profile.homeEquipment.isEmpty ? "bodyweight only" : profile.homeEquipment)
        Gym equipment: \(profile.gymEquipment.isEmpty ? "standard gym" : profile.gymEquipment)
        Target sessions per week: \(profile.daysPerWeek)
        """
    }

    // MARK: - Planner prompts

    static let plannerSystemPrompt = """
    \(safetyRules)

    Your task: design the NEXT WEEK of training as a block of sessions — one \
    per training day the client wants. The block is a skeleton; each day it \
    is adapted to the client's energy, venue, and time, so:
    - Give every session a clear focus and a sensible default venue-neutral \
    design, plus a homeAlternativeNote explaining how to run it with only \
    home equipment.
    - Build in progression from the coach's memory (the wiki): continue \
    current working weights/progressions, nudging them up only where recent \
    feedback supports it.
    - Balance the week: alternate hard and easy days, vary muscle groups and \
    styles, respect the target number of sessions.

    Output format: respond with ONLY a JSON object, no markdown fences:
    {
      "rationale": "2-3 sentences explaining this week's structure for the client",
      "sessions": [
        {
          "focus": "Lower-body strength",
          "style": "weightlifting",
          "durationMinutes": 40,
          "homeAlternativeNote": "how to do this session at home, or null if unchanged",
          "exercises": [
            {"name": "Exercise name", "sets": 3, "reps": "8-10", "weight": "12 kg or null", "restSeconds": 60, "notes": "optional cue"}
          ]
        }
      ]
    }
    """

    static func plannerUserPrompt(
        profile: UserProfile,
        wikiContext: String,
        lastBlockSummary: String?
    ) -> String {
        """
        COACH'S MEMORY (wiki)
        \(wikiContext)

        \(profileConstraints(profile))

        PREVIOUS BLOCK
        \(lastBlockSummary ?? "None — this is the first planned week. Start conservatively.")

        Plan next week now: exactly \(profile.daysPerWeek) sessions. Return only the JSON object.
        """
    }

    // MARK: - Modulator prompts

    static let modulatorSystemPrompt = """
    \(safetyRules)

    Your task: produce TODAY'S concrete workout. Usually you adapt the \
    planned session you are given — keep its intent and progression targets, \
    but modulate for today's reality:
    - Low energy, soreness, or a bad mood: cut volume/intensity, or swap to \
    an easier style or a recovery session. Keep it something they can win at.
    - Less time than planned: trim accessories, keep the core work.
    - Venue "home": use only home equipment (see the session's home \
    alternative note if present).
    - Good energy and positive recent feedback: run the session as designed, \
    with at most a small extra challenge.
    If no planned session is given, design a sensible standalone workout for \
    today from the coach's memory instead.

    Output format: respond with ONLY a JSON object, no markdown fences, \
    matching exactly this schema:
    \(workoutJSONSchema)
    """

    static func modulatorUserPrompt(
        profile: UserProfile,
        wikiContext: String,
        session: PlannedSession?,
        checkIn: DailyCheckIn
    ) -> String {
        var lines: [String] = []
        lines.append("COACH'S MEMORY (wiki)")
        lines.append(wikiContext)
        lines.append("")
        lines.append(profileConstraints(profile))
        lines.append("")
        lines.append("TODAY'S PLANNED SESSION")
        if let session {
            lines.append(session.summaryLine)
            if let note = session.homeAlternativeNote, !note.isEmpty {
                lines.append("Home alternative: \(note)")
            }
            for exercise in session.exercises {
                let weight = exercise.weight.map { " @ \($0)" } ?? ""
                lines.append("- \(exercise.name): \(exercise.sets)×\(exercise.reps)\(weight), rest \(exercise.restSeconds)s\(exercise.notes.map { " (\($0))" } ?? "")")
            }
        } else {
            lines.append("None — design a standalone workout for today.")
        }
        lines.append("")
        lines.append("TODAY'S CHECK-IN")
        lines.append("Energy: \(checkIn.energy.rawValue)")
        lines.append("Mood: \(checkIn.moodText.isEmpty ? "not specified" : checkIn.moodText)")
        lines.append("Soreness or pain: \(checkIn.sorenessOrPain.isEmpty ? "none reported" : checkIn.sorenessOrPain)")
        lines.append("Venue: \(checkIn.venue.rawValue)")
        lines.append("Time available: \(checkIn.minutesAvailable) minutes")
        if let preferred = checkIn.preferredStyle {
            lines.append("Requested style for today: \(preferred.rawValue)")
        }
        lines.append("")
        lines.append("Produce today's workout now. Return only the JSON object.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Chat prompts

    static func chatSystemPrompt(
        profile: UserProfile,
        wikiContext: String,
        workout: Workout
    ) -> String {
        let workoutJSON: String
        if let data = try? JSONEncoder().encode(workout.asGenerated),
           let string = String(data: data, encoding: .utf8) {
            workoutJSON = string
        } else {
            workoutJSON = "unavailable"
        }
        return """
        \(safetyRules)

        You are chatting with the client about TODAY'S workout. Answer \
        questions, explain choices, and when they ask for a change (swap an \
        exercise, make it easier, their wrists hurt, etc.), apply it.

        COACH'S MEMORY (wiki)
        \(wikiContext)

        \(profileConstraints(profile))

        TODAY'S CURRENT WORKOUT (JSON)
        \(workoutJSON)

        Output format: respond with ONLY a JSON object, no markdown fences:
        {
          "reply": "your conversational reply to the client, brief and warm",
          "updatedWorkout": null
        }
        If and only if the client's message requires changing the workout, set \
        "updatedWorkout" to the COMPLETE new workout JSON (same schema as the \
        current workout above, all fields present). Otherwise keep it null.
        """
    }

    // MARK: - Scribe prompts

    static let scribeSystemPrompt = """
    You are the record-keeper for a personal trainer. After each completed \
    workout you update the coach's memory — a small markdown wiki.

    \(WikiSchema.conventions)

    Update guidance:
    - "log": always append one entry for this session.
    - "progressions": update only movements trained today, copying numbers \
    verbatim from the workout data (use actuals where the client adjusted).
    - "observations": add or refine a pattern only if today's data genuinely \
    supports one (recurring discomfort, energy patterns, clear preferences). \
    Do not speculate from a single data point.
    - "current-block": update the week's progress.
    - "profile": only if the workout revealed a durable new fact.

    Output format: respond with ONLY a JSON object, no markdown fences:
    {"pages": {"slug": "full new markdown content of that page"}}
    Include only pages that need changes; each value replaces the whole page.
    """

    static func scribeUserPrompt(wikiContext: String, workout: Workout) -> String {
        var lines: [String] = []
        lines.append("CURRENT WIKI")
        lines.append(wikiContext)
        lines.append("")
        lines.append("COMPLETED WORKOUT (raw data, ground truth)")
        lines.append(workout.historyLine)
        lines.append("Check-in was: energy \(workout.checkIn.energy.rawValue), venue \(workout.checkIn.venue.rawValue), \(workout.checkIn.minutesAvailable) min available" +
                     (workout.checkIn.moodText.isEmpty ? "" : ", mood: \(workout.checkIn.moodText)") +
                     (workout.checkIn.sorenessOrPain.isEmpty ? "" : ", soreness: \(workout.checkIn.sorenessOrPain)"))
        lines.append("Exercises:")
        for exercise in workout.exercises {
            lines.append("- \(exercise.performedSummary)")
        }
        if let duration = workout.actualDurationMinutes {
            lines.append("Actual duration: \(duration) minutes")
        }
        if let rating = workout.feedbackRating {
            lines.append("Post-workout feeling: \(rating)/5" + (workout.feedbackText.flatMap { $0.isEmpty ? nil : ": \"\($0)\"" } ?? ""))
        }
        lines.append("")
        lines.append("Update the wiki now. Return only the JSON object.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Rebuild prompts

    static let rebuildSystemPrompt = """
    You are the record-keeper for a personal trainer. The coach's memory (a \
    small markdown wiki) needs to be REBUILT from scratch from the raw \
    training history, because the current wiki may have drifted or bloated.

    \(WikiSchema.conventions)

    Rebuild guidance:
    - Produce ALL pages listed above, complete and lean.
    - Derive progressions from the most recent occurrences of each movement; \
    copy numbers verbatim from the history lines.
    - Observations should reflect patterns across the whole history.
    - The log gets the most recent sessions only (respect its entry cap).

    Output format: respond with ONLY a JSON object, no markdown fences:
    {"pages": {"slug": "full new markdown content of that page"}}
    """

    static func rebuildUserPrompt(profile: UserProfile, historyLines: [String]) -> String {
        """
        CLIENT PROFILE (ground truth)
        Name: \(profile.name)
        Goal: \(profile.primaryGoal)
        Experience: \(profile.experienceRaw), target \(profile.daysPerWeek) sessions/week
        Medical notes: \(profile.medicalNotes.isEmpty ? "none reported" : profile.medicalNotes)
        Limitations: \(profile.injuriesOrLimitations.isEmpty ? "none reported" : profile.injuriesOrLimitations)

        \(profileConstraints(profile))

        FULL WORKOUT HISTORY (oldest first, one line per session)
        \(historyLines.isEmpty ? "No workouts yet." : historyLines.joined(separator: "\n"))

        Rebuild the whole wiki now. Return only the JSON object.
        """
    }

    // MARK: - Parsing

    /// Decodes a JSON payload from a model reply, tolerating markdown
    /// fences or stray prose around the JSON object.
    static func parse<T: Decodable>(_ raw: String) throws -> T {
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
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw LLMError.invalidJSON(underlying: error)
        }
    }
}
