import Foundation
import SwiftData

enum ChatRole: String, Codable {
    case user, assistant
}

/// One message in a workout's chat thread with the coach.
/// Part of the raw layer: transcripts are ground truth for wiki rebuilds.
@Model
final class CoachChatMessage {
    var workoutUUID: UUID
    var roleRaw: String
    var content: String
    var date: Date

    init(workoutUUID: UUID, role: ChatRole, content: String) {
        self.workoutUUID = workoutUUID
        self.roleRaw = role.rawValue
        self.content = content
        self.date = .now
    }

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
}
