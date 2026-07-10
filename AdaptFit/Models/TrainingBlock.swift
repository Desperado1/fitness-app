import Foundation
import SwiftData

enum BlockStatus: String, Codable {
    case active, completed, abandoned
}

/// One planned session inside a weekly block. The daily Modulator turns
/// this into a concrete Workout based on the day's check-in.
struct PlannedSession: Codable, Hashable, Identifiable {
    var index: Int
    /// e.g. "Lower-body strength", "Easy intervals + core".
    var focus: String
    var style: String
    var durationMinutes: Int
    /// How to run this session with home equipment if the user isn't at the gym.
    var homeAlternativeNote: String?
    var exercises: [PrescribedExercise]

    var id: Int { index }

    var trainingStyle: TrainingStyle { TrainingStyle(rawValue: style) ?? .recovery }

    var summaryLine: String {
        "Session \(index + 1): \(focus) [\(style), \(durationMinutes) min]"
    }
}

/// A week of planned training. The skeleton the daily check-in modulates within.
@Model
final class TrainingBlock {
    var startDate: Date
    var statusRaw: String
    /// The coach's reasoning for this week's structure — shown in PlanView.
    var rationale: String
    var sessions: [PlannedSession]
    var completedSessionIndices: [Int]
    var createdAt: Date

    init(startDate: Date, generated: GeneratedBlock) {
        self.startDate = startDate
        self.statusRaw = BlockStatus.active.rawValue
        self.rationale = generated.rationale
        // Index by array order so the contract stays simple for the LLM.
        self.sessions = generated.sessions.enumerated().map { index, session in
            PlannedSession(
                index: index,
                focus: session.focus,
                style: session.style,
                durationMinutes: session.durationMinutes,
                homeAlternativeNote: session.homeAlternativeNote,
                exercises: session.exercises
            )
        }
        self.completedSessionIndices = []
        self.createdAt = .now
    }

    var status: BlockStatus {
        get { BlockStatus(rawValue: statusRaw) ?? .abandoned }
        set { statusRaw = newValue.rawValue }
    }

    var nextPendingSession: PlannedSession? {
        sessions.first { !completedSessionIndices.contains($0.index) }
    }

    func markSessionCompleted(_ index: Int) {
        if !completedSessionIndices.contains(index) {
            completedSessionIndices.append(index)
        }
        if completedSessionIndices.count >= sessions.count {
            status = .completed
        }
    }

    /// Compact summary of the block for the next planner prompt.
    var summary: String {
        let done = completedSessionIndices.count
        var lines = ["Week of \(startDate.formatted(date: .abbreviated, time: .omitted)) (\(statusRaw), \(done)/\(sessions.count) sessions done):"]
        lines += sessions.map { "  - \($0.summaryLine)\(completedSessionIndices.contains($0.index) ? " ✓" : "")" }
        return lines.joined(separator: "\n")
    }
}

// MARK: - LLM JSON contract

struct GeneratedBlock: Codable {
    struct Session: Codable {
        var focus: String
        var style: String
        var durationMinutes: Int
        var homeAlternativeNote: String?
        var exercises: [PrescribedExercise]
    }

    var rationale: String
    var sessions: [Session]
}
