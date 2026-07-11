import Foundation

/// The schema layer of the coach's memory: which pages exist, what belongs
/// on each, and the conventions that keep the LLM a disciplined wiki
/// maintainer instead of a freeform chatbot. Shared by every coach role.
enum WikiSlug: String, CaseIterable, Identifiable {
    case profile
    case progressions
    case observations
    case currentBlock = "current-block"
    case log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "Profile"
        case .progressions: return "Progressions"
        case .observations: return "Observations"
        case .currentBlock: return "Current Block"
        case .log: return "Coach's Log"
        }
    }

    var purpose: String {
        switch self {
        case .profile:
            return "Stable facts: goals, medical context, equipment at home and gym, hard constraints. Changes rarely."
        case .progressions:
            return "Current working numbers per movement pattern, e.g. \"goblet squat: 3×10 @ 12 kg (last increased 2026-07-02)\". Numbers must be copied verbatim from the raw workout data, never estimated."
        case .observations:
            return "Patterns noticed over time: energy rhythms, exercises that cause discomfort, preferences, what has and hasn't worked."
        case .currentBlock:
            return "The active weekly plan: its rationale, sessions, and how the week is going so far."
        case .log:
            return "Append-only journal, one short line per session, newest last. Format: \"YYYY-MM-DD: <what happened, how it felt>\"."
        }
    }

    /// Hard size budget in characters — the wiki must stay lean enough
    /// to inline into every prompt.
    var budgetChars: Int {
        switch self {
        case .log: return 2000
        default: return 1500
        }
    }

    /// Max bullet entries kept on the log page.
    static let logMaxEntries = 20
}

enum WikiSchema {
    /// The conventions text included in every wiki-writing prompt.
    static var conventions: String {
        var lines: [String] = []
        lines.append("The coach's memory is a wiki of exactly these markdown pages:")
        for slug in WikiSlug.allCases {
            lines.append("- \"\(slug.rawValue)\" (\(slug.title), max \(slug.budgetChars) characters): \(slug.purpose)")
        }
        lines.append("""

        Wiki rules:
        - Keep pages LEAN. Prefer rewriting and condensing over appending. Delete stale details.
        - Never invent or estimate numbers: weights, reps, and dates come only from the raw data provided in the prompt.
        - The "log" page keeps at most \(WikiSlug.logMaxEntries) entries; drop the oldest when adding new ones.
        - Plain markdown: short headers and bullet points. No tables, no emojis.
        - Only include pages that actually need changes in your response.
        """)
        return lines.joined(separator: "\n")
    }

    /// Enforces per-page size budgets. Non-log pages keep their beginning;
    /// the log keeps its newest (last) entries.
    static func enforceBudget(_ content: String, for slug: WikiSlug) -> String {
        var result = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if slug == .log {
            var lines = result.components(separatedBy: "\n")
            let bulletIndices = lines.indices.filter { lines[$0].hasPrefix("- ") }
            if bulletIndices.count > WikiSlug.logMaxEntries {
                let dropCount = bulletIndices.count - WikiSlug.logMaxEntries
                let toDrop = Set(bulletIndices.prefix(dropCount))
                lines = lines.indices.filter { !toDrop.contains($0) }.map { lines[$0] }
                result = lines.joined(separator: "\n")
            }
            // If still over budget, trim from the top (oldest first), at line boundaries.
            while result.count > slug.budgetChars {
                var lines = result.components(separatedBy: "\n")
                guard lines.count > 1 else {
                    result = String(result.suffix(slug.budgetChars))
                    break
                }
                lines.removeFirst()
                result = lines.joined(separator: "\n")
            }
            return result
        }

        // Other pages: keep the beginning, cut at a line boundary.
        guard result.count > slug.budgetChars else { return result }
        var kept: [String] = []
        var total = 0
        for line in result.components(separatedBy: "\n") {
            if total + line.count + 1 > slug.budgetChars { break }
            kept.append(line)
            total += line.count + 1
        }
        if kept.isEmpty {
            return String(result.prefix(slug.budgetChars))
        }
        return kept.joined(separator: "\n")
    }
}
