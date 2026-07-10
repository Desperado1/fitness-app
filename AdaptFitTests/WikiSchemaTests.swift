import XCTest
@testable import AdaptFit

final class WikiSchemaTests: XCTestCase {
    func testShortContentPassesThroughUnchanged() {
        let content = "# Progressions\n- Goblet squat: 3x10 @ 12 kg"
        XCTAssertEqual(WikiSchema.enforceBudget(content, for: .progressions), content)
    }

    func testLongPageTruncatesAtLineBoundaryWithinBudget() {
        let line = String(repeating: "x", count: 100)
        let content = (0..<40).map { "\(line) \($0)" }.joined(separator: "\n")
        let result = WikiSchema.enforceBudget(content, for: .observations)
        XCTAssertLessThanOrEqual(result.count, WikiSlug.observations.budgetChars)
        // Keeps the beginning of the page.
        XCTAssertTrue(result.hasPrefix(line))
        // Cuts on whole lines only.
        XCTAssertTrue(result.components(separatedBy: "\n").allSatisfy { $0.hasPrefix(line) })
    }

    func testLogKeepsOnlyNewestEntries() {
        let bullets = (1...30).map { "- 2026-07-\(String(format: "%02d", $0)): session \($0)" }
        let content = "# Coach's Log\n" + bullets.joined(separator: "\n")
        let result = WikiSchema.enforceBudget(content, for: .log)
        let keptBullets = result.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        XCTAssertEqual(keptBullets.count, WikiSlug.logMaxEntries)
        // Newest (last) entries survive, oldest are dropped.
        XCTAssertTrue(keptBullets.last?.contains("session 30") ?? false)
        XCTAssertTrue(keptBullets.first?.contains("session 11") ?? false)
        // Header before the bullets is preserved.
        XCTAssertTrue(result.hasPrefix("# Coach's Log"))
    }

    func testConventionsMentionEveryPage() {
        for slug in WikiSlug.allCases {
            XCTAssertTrue(
                WikiSchema.conventions.contains("\"\(slug.rawValue)\""),
                "Conventions must describe page \(slug.rawValue)"
            )
        }
    }
}
