import Foundation
import SwiftData

struct WikiSnapshot: Codable, Hashable {
    var content: String
    var savedAt: Date
}

/// One page of the coach's memory — LLM-maintained markdown, user-editable.
/// The raw SwiftData records remain ground truth; every page can be rebuilt
/// from history, so losing or mangling wiki content is always recoverable.
@Model
final class WikiPage {
    var slug: String
    var content: String
    var updatedAt: Date
    /// Previous versions, newest first, capped by WikiStore for rollback.
    var snapshots: [WikiSnapshot]

    init(slug: String, content: String) {
        self.slug = slug
        self.content = content
        self.updatedAt = .now
        self.snapshots = []
    }
}
