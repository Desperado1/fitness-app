import Foundation
import SwiftData

/// Manages the wiki layer: seeding, reading pages into prompt context,
/// applying scribe/rebuild updates (with snapshots and size budgets).
/// Always used with the main ModelContext on the main actor.
struct WikiStore {
    let context: ModelContext

    private static let maxSnapshots = 10

    /// Creates the five pages on first run. Safe to call repeatedly.
    func ensureSeeded(profile: UserProfile) {
        let existing = Set(allPages().map(\.slug))
        for slug in WikiSlug.allCases where !existing.contains(slug.rawValue) {
            context.insert(WikiPage(slug: slug.rawValue, content: Self.seedContent(for: slug, profile: profile)))
        }
    }

    func page(for slug: WikiSlug) -> WikiPage? {
        allPages().first { $0.slug == slug.rawValue }
    }

    /// All pages in canonical slug order.
    func allPages() -> [WikiPage] {
        let pages = (try? context.fetch(FetchDescriptor<WikiPage>())) ?? []
        let order = Dictionary(uniqueKeysWithValues: WikiSlug.allCases.enumerated().map { ($1.rawValue, $0) })
        return pages.sorted { (order[$0.slug] ?? .max) < (order[$1.slug] ?? .max) }
    }

    /// The full wiki as a single string for inclusion in prompts.
    func contextString() -> String {
        allPages().map { page in
            "### \(page.slug)\n\(page.content)"
        }
        .joined(separator: "\n\n")
    }

    /// Applies LLM-produced page updates: snapshots the old content,
    /// enforces the size budget, ignores unknown slugs.
    func apply(updates: [String: String]) {
        for (slugRaw, newContent) in updates {
            guard let slug = WikiSlug(rawValue: slugRaw),
                  let page = page(for: slug) else { continue }
            let budgeted = WikiSchema.enforceBudget(newContent, for: slug)
            guard budgeted != page.content, !budgeted.isEmpty else { continue }
            page.snapshots.insert(WikiSnapshot(content: page.content, savedAt: page.updatedAt), at: 0)
            if page.snapshots.count > Self.maxSnapshots {
                page.snapshots.removeLast(page.snapshots.count - Self.maxSnapshots)
            }
            page.content = budgeted
            page.updatedAt = .now
        }
    }

    func restore(page: WikiPage, snapshot: WikiSnapshot) {
        page.snapshots.insert(WikiSnapshot(content: page.content, savedAt: page.updatedAt), at: 0)
        page.content = snapshot.content
        page.updatedAt = .now
    }

    // MARK: - Seeds

    static func seedContent(for slug: WikiSlug, profile: UserProfile) -> String {
        switch slug {
        case .profile:
            return """
            # Profile
            - Name: \(profile.name)
            - Goal: \(profile.primaryGoal.isEmpty ? "not specified" : profile.primaryGoal)
            - Experience: \(profile.experienceRaw), target \(profile.daysPerWeek) sessions/week
            - Medical: \(profile.medicalNotes.isEmpty ? "none reported" : profile.medicalNotes)
            - Limitations: \(profile.injuriesOrLimitations.isEmpty ? "none reported" : profile.injuriesOrLimitations)
            - Home equipment: \(profile.homeEquipment.isEmpty ? "bodyweight only" : profile.homeEquipment)
            - Gym equipment: \(profile.gymEquipment.isEmpty ? "standard gym" : profile.gymEquipment)
            - Styles enabled: \(profile.allowedStyles.map(\.rawValue).joined(separator: ", "))
            """
        case .progressions:
            return "# Progressions\nNo training data yet."
        case .observations:
            return "# Observations\nNothing observed yet — first sessions will tell."
        case .currentBlock:
            return "# Current Block\nNo plan yet. Use \"Plan my week\" to create the first block."
        case .log:
            return "# Coach's Log\n"
        }
    }
}
