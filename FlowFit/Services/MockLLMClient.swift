import Foundation

/// Offline coach used when the app is launched with -mock-llm:
/// UI tests in CI (no API key) and demoing without burning credits.
/// Detects the role from the system prompt and returns canned JSON
/// matching the real contracts.
struct MockLLMClient: LLMCompleting {
    func complete(messages: [LLMMessage], maxTokens: Int) async throws -> String {
        // Small delay so loading states are visible and screenshots stable.
        try? await Task.sleep(for: .milliseconds(300))

        let system = messages.first(where: { $0.role == "system" })?.content ?? ""
        if system.contains("greeting the client at the start of their training day") {
            // Scripted three-turn check-in, so the mock walks a real
            // conversation instead of repeating one canned reply. Counted by
            // replies already given — the opening turn sends a synthetic user
            // message that never lands in the transcript, so counting user
            // messages would stick on turn 1.
            return Self.intakeJSON(turn: messages.filter { $0.role == "assistant" }.count + 1)
        }
        if system.contains("design the NEXT WEEK") {
            return Self.blockJSON
        }
        if system.contains("TODAY'S concrete workout") {
            let user = messages.first(where: { $0.role == "user" })?.content ?? ""
            return user.contains("DIFFERENT ALTERNATIVE") ? Self.alternativeWorkoutJSON : Self.workoutJSON
        }
        if system.contains("chatting with the client") {
            return Self.chatJSON
        }
        if system.contains("REBUILT") {
            return Self.rebuildJSON
        }
        if system.contains("record-keeper") {
            return Self.scribeJSON
        }
        return Self.workoutJSON
    }

    /// The conversational check-in, one canned turn at a time: greet, learn
    /// energy and soreness, then venue and time — and hand over.
    static func intakeJSON(turn: Int) -> String {
        switch turn {
        case ...1:
            return """
            {
              "reply": "Morning! Today's a lower-body strength day. How are you feeling?",
              "readyToGenerate": false
            }
            """
        case 2:
            return """
            {
              "reply": "Thanks for telling me — we'll go gentle on those calves. Where are you training today, and how long have you got?",
              "checkIn": {"energy": "low", "moodText": "tired but willing", "sorenessOrPain": "calves sore"},
              "readyToGenerate": false
            }
            """
        default:
            return """
            {
              "reply": "Perfect — half an hour at home. Let me put something together for you.",
              "checkIn": {"venue": "home", "minutesAvailable": 30},
              "readyToGenerate": true
            }
            """
        }
    }

    static let blockJSON = """
    {
      "rationale": "A gentle, balanced week: two strength days to keep rebuilding your base, one easy recovery day in between so consistency stays comfortable.",
      "sessions": [
        {
          "focus": "Lower-body strength",
          "style": "weightlifting",
          "durationMinutes": 35,
          "homeAlternativeNote": "Use the dumbbells for goblet squats and hip hinges instead of gym machines.",
          "exercises": [
            {"name": "Goblet Squat", "sets": 3, "reps": "8-10", "weight": "12 kg", "restSeconds": 90, "notes": "Chest tall, sit back"},
            {"name": "Glute Bridge", "sets": 3, "reps": "12", "weight": null, "restSeconds": 60, "notes": "Squeeze at the top"},
            {"name": "Romanian Deadlift", "sets": 3, "reps": "10", "weight": "10 kg dumbbells", "restSeconds": 90, "notes": null}
          ]
        },
        {
          "focus": "Upper-body calisthenics",
          "style": "calisthenics",
          "durationMinutes": 30,
          "homeAlternativeNote": null,
          "exercises": [
            {"name": "Incline Push-up", "sets": 3, "reps": "8", "weight": null, "restSeconds": 60, "notes": "Hands on a sturdy table"},
            {"name": "Band Row", "sets": 3, "reps": "12", "weight": "light band", "restSeconds": 60, "notes": null},
            {"name": "Bird Dog", "sets": 3, "reps": "8 per side", "weight": null, "restSeconds": 45, "notes": "Slow and controlled"}
          ]
        },
        {
          "focus": "Recovery walk and mobility",
          "style": "recovery",
          "durationMinutes": 25,
          "homeAlternativeNote": null,
          "exercises": [
            {"name": "Brisk Walk", "sets": 1, "reps": "15 min easy pace", "weight": null, "restSeconds": 0, "notes": null},
            {"name": "Hip Flexor Stretch", "sets": 2, "reps": "30 sec per side", "weight": null, "restSeconds": 15, "notes": null}
          ]
        }
      ]
    }
    """

    static let workoutJSON = """
    {
      "title": "Steady Strength",
      "style": "weightlifting",
      "intensity": "moderate",
      "durationMinutes": 30,
      "warmup": ["5 min easy walk", "10 bodyweight squats", "Arm circles"],
      "exercises": [
        {"name": "Goblet Squat", "sets": 3, "reps": "8-10", "weight": "12 kg", "restSeconds": 90, "notes": "Chest tall, sit back"},
        {"name": "Glute Bridge", "sets": 3, "reps": "12", "weight": null, "restSeconds": 60, "notes": "Squeeze at the top"},
        {"name": "Incline Push-up", "sets": 3, "reps": "8", "weight": null, "restSeconds": 60, "notes": null}
      ],
      "cooldown": ["Hamstring stretch", "Deep breathing, 1 min"],
      "coachNote": "Energy looked steady today, so we run the planned strength work with one accessory trimmed to fit your time.",
      "safetyNote": "Keep breathing steadily through every rep and stop if anything pinches or feels off."
    }
    """

    /// Returned when the modulator is asked for a different alternative
    /// (the "try a different workout" regeneration). Distinct title and
    /// exercises from workoutJSON so the change is visible.
    static let alternativeWorkoutJSON = """
    {
      "title": "Gentle Mobility Flow",
      "style": "recovery",
      "intensity": "low",
      "durationMinutes": 30,
      "warmup": ["3 min easy march in place", "Cat-cow x8"],
      "exercises": [
        {"name": "Bodyweight Good Morning", "sets": 3, "reps": "10", "weight": null, "restSeconds": 45, "notes": "Soft knees, flat back"},
        {"name": "Bird Dog", "sets": 3, "reps": "8 per side", "weight": null, "restSeconds": 45, "notes": "Slow and controlled"},
        {"name": "Band Pull-apart", "sets": 3, "reps": "15", "weight": "light band", "restSeconds": 45, "notes": null}
      ],
      "cooldown": ["Child's pose, 1 min", "Box breathing, 1 min"],
      "coachNote": "Here's a lighter, mobility-focused take on today — same time, easier on the joints.",
      "safetyNote": "Move within a comfortable range and stop if anything pinches."
    }
    """

    static let chatJSON = """
    {
      "reply": "Good call telling me — I've swapped the incline push-ups for band rows so your wrists stay neutral today. Everything else stays the same.",
      "updatedWorkout": {
        "title": "Steady Strength",
        "style": "weightlifting",
        "intensity": "moderate",
        "durationMinutes": 30,
        "warmup": ["5 min easy walk", "10 bodyweight squats", "Arm circles"],
        "exercises": [
          {"name": "Goblet Squat", "sets": 3, "reps": "8-10", "weight": "12 kg", "restSeconds": 90, "notes": "Chest tall, sit back"},
          {"name": "Glute Bridge", "sets": 3, "reps": "12", "weight": null, "restSeconds": 60, "notes": "Squeeze at the top"},
          {"name": "Band Row", "sets": 3, "reps": "12", "weight": "light band", "restSeconds": 60, "notes": "Elbows close to the body"}
        ],
        "cooldown": ["Hamstring stretch", "Deep breathing, 1 min"],
        "coachNote": "Swapped push-ups for band rows to keep your wrists happy.",
        "safetyNote": "Keep breathing steadily through every rep and stop if anything pinches or feels off."
      }
    }
    """

    static let scribeJSON = """
    {
      "pages": {
        "log": "# Coach's Log\\n- 2026-07-10: Steady Strength (weightlifting, 30 min) — felt 4/5, goblet squat adjusted to 10 kg.",
        "progressions": "# Progressions\\n- Goblet squat: 3×8-10 @ 10 kg (last session)\\n- Glute bridge: 3×12 bodyweight\\n- Band row: 3×12 light band",
        "current-block": "# Current Block\\nWeek in progress: session 1 of 3 done (lower-body strength). Next: upper-body calisthenics."
      }
    }
    """

    static let rebuildJSON = """
    {
      "pages": {
        "profile": "# Profile\\n- Goal: rebuild strength\\n- Medical: postpartum recovery, PCOD, mild thyroid issue\\n- Prefers steady, winnable sessions.",
        "progressions": "# Progressions\\n- Goblet squat: 3×8-10 @ 10 kg\\n- Glute bridge: 3×12 bodyweight",
        "observations": "# Observations\\n- Wrists dislike straight-arm pressure; band pulls work well.\\n- Responds well to moderate steady sessions.",
        "current-block": "# Current Block\\nWeek in progress: 1 of 3 sessions done.",
        "log": "# Coach's Log\\n- 2026-07-10: Steady Strength — felt 4/5."
      }
    }
    """
}
