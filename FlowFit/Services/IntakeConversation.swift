import Foundation

/// One check-in conversation, owned by `TodayView` and shared by every
/// surface that can hold it — the voice screen and the typed sheet.
///
/// Extracted rather than duplicated on purpose: this holds field
/// application, the ready-latch and error recovery, and two copies of that
/// drifting apart would be a real bug. It is also what makes "talking and
/// tapping are two ways into one state" true *across screens* rather than
/// only within one.
@MainActor
final class IntakeConversation: ObservableObject {
    @Published var checkIn = DailyCheckIn()
    /// Which fields have actually been established — by the conversation or
    /// by hand. Every field has a usable default, so the values alone can't
    /// tell an answer from an untouched default, and the intake coach needs
    /// that difference to know what's left to ask.
    @Published var knownFields: Set<CheckInField> = []
    @Published private(set) var transcript: [IntakeTurn] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    /// Latches on: once the coach has said it has enough, a later turn that
    /// only adds colour shouldn't take the hand-off away again.
    private var coachSaysReady = false

    /// Resolved per turn rather than held, so a provider or key changed in
    /// Settings takes effect on the next message. Also the seam the tests
    /// use to run a whole conversation without a network.
    var makeCoach: () -> CoachService = { CoachService.fromSettings() }

    private var profile: UserProfile?
    private var session: PlannedSession?
    /// A closure rather than a string so the wiki isn't re-read on every
    /// render, and so a turn late in the conversation sees current pages.
    private var wikiContext: () -> String = { "" }

    /// Offer the hand-off once the coach says so, or once everything it
    /// needs is known by any route.
    var isReady: Bool {
        coachSaysReady || CheckInField.required.allSatisfy { knownFields.contains($0) }
    }

    /// Cheap and idempotent — call it whenever the plan or the wiki could
    /// have changed. Does not touch the transcript.
    func configure(
        profile: UserProfile,
        session: PlannedSession?,
        wikiContext: @escaping () -> String
    ) {
        self.profile = profile
        self.session = session
        self.wikiContext = wikiContext
    }

    /// The coach speaks first, but only once — reopening a surface
    /// continues the conversation rather than restarting it.
    func startIfNeeded() {
        guard transcript.isEmpty else { return }
        transcript.append(IntakeTurn(role: .assistant, content: openingLine))
    }

    /// Written locally rather than asked of the model. It's the same every
    /// day and the planned session is already on the device, so spending two
    /// seconds of round-trip on it would put a silence exactly where the
    /// client is deciding whether this thing is worth talking to.
    var openingLine: String {
        let name = profile?.name ?? "there"
        guard let session else {
            return "Hi \(name)! No plan running this week, so we'll put together a one-off. How are you feeling today?"
        }
        return "Hi \(name)! Today's \(session.focus.lowercased()). How are you feeling?"
    }

    /// The last thing the coach said, so a surface joining part-way through
    /// can pick up in context instead of cold.
    var lastCoachLine: String? {
        transcript.last(where: { $0.role == .assistant })?.content
    }

    /// One turn with the coach. Returns what it said, so the voice loop can
    /// speak it; nil if the turn failed.
    @discardableResult
    func send(_ text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let profile else { return nil }

        isSending = true
        defer { isSending = false }

        // History as it stood before this turn — the new message is passed
        // separately, so it must not already be in the transcript.
        let history = transcript
        transcript.append(IntakeTurn(role: .user, content: trimmed))

        do {
            let reply = try await makeCoach().intake(
                profile: profile,
                wikiContext: wikiContext(),
                session: session,
                checkIn: checkIn,
                known: knownFields,
                history: history,
                userMessage: trimmed
            )
            if let patch = reply.checkIn {
                knownFields.formUnion(checkIn.apply(patch, allowedStyles: profile.allowedStyles))
            }
            transcript.append(IntakeTurn(role: .assistant, content: reply.reply))
            coachSaysReady = coachSaysReady || reply.isReadyToGenerate
            return reply.reply
        } catch {
            // Put the client's words back so the turn isn't silently lost.
            transcript.removeLast()
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Called once the turns have been written into the new workout's
    /// thread, so tomorrow starts a fresh conversation.
    func clearTranscript() {
        transcript.removeAll()
        coachSaysReady = false
    }
}
