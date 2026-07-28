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
    /// Sessions the user chose to skip. Like completed sessions, these are
    /// "resolved" — the plan advances past them — but tracked separately so
    /// the Plan UI and the next planner prompt can tell done from skipped.
    /// Defaulted so existing stores migrate without a custom migration plan.
    var skippedSessionIndices: [Int] = []
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
        self.skippedSessionIndices = []
        self.createdAt = .now
    }

    var status: BlockStatus {
        get { BlockStatus(rawValue: statusRaw) ?? .abandoned }
        set { statusRaw = newValue.rawValue }
    }

    var nextPendingSession: PlannedSession? {
        sessions.first { !isResolved($0.index) }
    }

    /// A session is resolved once it has been completed or skipped — either
    /// way the plan moves on to the next session.
    func isResolved(_ index: Int) -> Bool {
        completedSessionIndices.contains(index) || skippedSessionIndices.contains(index)
    }

    /// How many sessions are behind the user (done or skipped).
    var resolvedSessionCount: Int {
        Set(completedSessionIndices).union(skippedSessionIndices).count
    }

    func markSessionCompleted(_ index: Int) {
        // If it had been skipped, completing it wins.
        skippedSessionIndices.removeAll { $0 == index }
        if !completedSessionIndices.contains(index) {
            completedSessionIndices.append(index)
        }
        finishIfAllResolved()
    }

    func markSessionSkipped(_ index: Int) {
        // Don't override an already-completed session.
        guard !completedSessionIndices.contains(index) else { return }
        if !skippedSessionIndices.contains(index) {
            skippedSessionIndices.append(index)
        }
        finishIfAllResolved()
    }

    /// Once every session is resolved (done or skipped) the week is over.
    private func finishIfAllResolved() {
        if resolvedSessionCount >= sessions.count {
            status = .completed
        }
    }

    /// Compact summary of the block for the next planner prompt.
    var summary: String {
        let done = completedSessionIndices.count
        let skipped = skippedSessionIndices.count
        var header = "Week of \(startDate.formatted(date: .abbreviated, time: .omitted)) (\(statusRaw), \(done)/\(sessions.count) sessions done"
        if skipped > 0 { header += ", \(skipped) skipped" }
        header += "):"
        var lines = [header]
        lines += sessions.map { session in
            let mark: String
            if completedSessionIndices.contains(session.index) {
                mark = " ✓"
            } else if skippedSessionIndices.contains(session.index) {
                mark = " ✗ skipped"
            } else {
                mark = ""
            }
            return "  - \(session.summaryLine)\(mark)"
        }
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
