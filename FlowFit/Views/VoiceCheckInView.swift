import SwiftUI

/// The voice-first check-in: an orb, a line of transcript, and the fields
/// filling in underneath. No pickers, no composer, nothing to read.
///
/// After the first tap the whole check-in runs hands-free — the coach
/// speaks, listens, and moves on by itself, then builds the workout rather
/// than asking for a tap it exists to avoid.
struct VoiceCheckInView: View {
    @ObservedObject var conversation: IntakeConversation
    /// TodayView owns workout generation, so this view never runs the
    /// modulator — but it does have to show that it's happening. Handing
    /// off to a silent orb would put the longest wait of the whole
    /// conversation exactly where there's nothing to look at.
    let isGenerating: Bool
    /// Called when the conversation has everything it needs.
    let onGenerate: () -> Void

    @StateObject private var voice = VoiceSession()
    /// Whether the hands-free loop is running. Separate from `voice.phase`:
    /// the loop stays "on" across the silent moments between turns, and
    /// every step checks it so leaving is immediate.
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            VoiceOrb(phase: voice.phase, level: voice.level, size: 132) {
                orbTapped()
            }
            .sensoryFeedback(.success, trigger: voice.phase == .thinking)

            Text(caption)
                .font(.callout)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, Theme.screenPadding)
                .animation(.easeOut(duration: 0.2), value: caption)

            // The live half of the screen: what the coach just said, or what
            // it is hearing right now.
            Text(spokenLine)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.appTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
                .padding(.horizontal, Theme.screenPadding)

            Spacer(minLength: 0)

            KnownFieldsStrip(checkIn: conversation.checkIn, knownFields: conversation.knownFields)

            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Building your workout…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.vertical, 12)
            } else {
                Button(isRunning ? "Stop" : "Start talking") {
                    if isRunning { stop() } else { Task { await start() } }
                }
                .buttonStyle(.ghost)
                .accessibilityIdentifier("voiceStartStop")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        // Never leave the microphone open behind a screen that has gone.
        .onDisappear { stop() }
        .alert("Couldn't reach your coach", isPresented: .init(
            get: { conversation.errorMessage != nil || voice.errorMessage != nil },
            set: { if !$0 { conversation.errorMessage = nil; voice.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((conversation.errorMessage ?? voice.errorMessage ?? "")
                + "\n\nYou can still fill in the check-in by hand — switch to Form up top.")
        }
    }

    /// What the client should be looking at: their own words as they land,
    /// otherwise the coach's last line.
    private var spokenLine: String {
        if isGenerating { return "Putting today's session together for you." }
        if !voice.partialTranscript.isEmpty { return voice.partialTranscript }
        if let notice = voice.notice { return notice }
        return conversation.lastCoachLine ?? conversation.openingLine
    }

    private var caption: String {
        if isGenerating { return "Hang tight" }
        guard isRunning else {
            return conversation.transcript.isEmpty
                ? "Tap to talk it through with your coach"
                : "Tap to pick up where you left off"
        }
        return voice.phase.hint
    }

    // MARK: - The loop

    /// Tapping the orb cuts the coach off mid-sentence and hands the turn
    /// straight back. Being trapped in a monologue is exactly the feeling
    /// voice mode exists to avoid — and leaving is the Stop button's job,
    /// not this one's.
    private func orbTapped() {
        switch voice.phase {
        case .speaking, .thinking:
            // .thinking is audible too — it's the filler line — so the same
            // tap cuts that off and gets on with the answer.
            voice.interruptSpeaking()
        case .idle where !isRunning:
            Task { await start() }
        case .idle:
            // The loop stalled — several turns running, nothing was heard.
            // Pick it up again rather than leaving a live-looking screen
            // that does nothing when tapped.
            Task { await runTurn(speaking: nil) }
        default:
            break
        }
    }

    private func start() async {
        guard await voice.prepare() else {
            conversation.errorMessage = "I need microphone and speech access to talk. You can turn them on in Settings — or switch to Form and fill it in."
            return
        }
        isRunning = true
        conversation.startIfNeeded()
        // Re-speak the coach's last line, so joining part-way through a
        // typed conversation picks up in context.
        await runTurn(speaking: conversation.lastCoachLine)
    }

    private func stop() {
        isRunning = false
        voice.stop()
    }

    /// One hands-free turn: say something, listen for the answer, send it,
    /// then recurse on the reply. Recursion is safe — each turn suspends on
    /// real speech, so nothing accumulates.
    private func runTurn(speaking line: String?) async {
        guard isRunning else { return }
        if let line { await voice.speak(line) }
        guard isRunning else { return }

        // The coach has everything it needs, so finish the job.
        if conversation.isReady {
            stop()
            onGenerate()
            return
        }

        voice.listen { utterance in
            Task { await handle(utterance) }
        }
    }

    private func handle(_ utterance: String) async {
        // The round trip starts first and the filler talks *over* it. The
        // other order would serialise the two and make the filler cost
        // latency instead of hiding it.
        let pending = Task { await conversation.send(utterance) }
        await voice.fillThinkingPause()
        let reply = await pending.value

        guard let reply else {
            // The turn failed and the alert is up; don't keep listening into
            // a conversation that lost its last message.
            stop()
            return
        }
        await runTurn(speaking: reply)
    }
}
