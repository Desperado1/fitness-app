import SwiftUI

/// The conversational check-in: instead of tapping energy, venue, time and
/// style, the client talks and the coach fills them in. The chips under the
/// thread show what it has heard, so a misheard answer is visible immediately
/// and correctable by hand — the form on TodayView stays the source of truth.
///
/// In voice mode the same conversation runs hands-free: the coach speaks,
/// listens, and moves on by itself, with no taps between turns.
struct CheckInChatView: View {
    let profile: UserProfile
    let session: PlannedSession?
    let wikiContext: String

    @Binding var checkIn: DailyCheckIn
    @Binding var knownFields: Set<CheckInField>
    @Binding var transcript: [IntakeTurn]

    /// Called when the client accepts the coach's hand-off. TodayView owns
    /// workout generation, so this view never runs the modulator itself.
    let onGenerate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceSession()

    @State private var input = ""
    @State private var isSending = false
    @State private var coachSaysReady = false
    @State private var voiceMode = false
    @State private var errorMessage: String?

    /// Offer the hand-off once the coach says so, or once everything it needs
    /// is known by any route. Derived from the bound `knownFields` rather than
    /// held only in local state, so closing and reopening the sheet doesn't
    /// lose a conversation that had already finished.
    private var isReady: Bool {
        coachSaysReady || CheckInField.required.allSatisfy { knownFields.contains($0) }
    }

    /// Written locally rather than asked of the model. It's the same every
    /// day and the planned session is already on the device, so spending two
    /// seconds of round-trip on it would put a silence exactly where the
    /// client is deciding whether this thing is worth talking to.
    private var openingLine: String {
        guard let session else {
            return "Hi \(profile.name)! No plan running this week, so we'll put together a one-off. How are you feeling today?"
        }
        return "Hi \(profile.name)! Today's \(session.focus.lowercased()). How are you feeling?"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                thread
                Rectangle().fill(Color.appBorder).frame(height: 1)
                knownStrip
                if voiceMode {
                    voiceControls
                } else {
                    composer
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Your coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Adjust by hand") {
                        voice.stop()
                        dismiss()
                    }
                    .accessibilityIdentifier("intakeAdjustByHand")
                }
            }
            .alert("Couldn't reach your coach", isPresented: .init(
                get: { errorMessage != nil || voice.errorMessage != nil },
                set: { if !$0 { errorMessage = nil; voice.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text((errorMessage ?? voice.errorMessage ?? "") + "\n\nYou can still fill in the check-in by hand.")
            }
        }
        .task {
            // The coach speaks first, but only once — reopening the sheet
            // continues the conversation rather than restarting it.
            if transcript.isEmpty {
                transcript.append(IntakeTurn(role: .assistant, content: openingLine))
            }
        }
        .onDisappear {
            // Never leave the microphone open behind a dismissed sheet.
            voice.stop()
        }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(transcript) { turn in
                        bubble(for: turn).id(turn.id)
                    }
                    if !voice.partialTranscript.isEmpty {
                        // Show speech as it lands, so the client can see they
                        // are being heard before the turn is over.
                        bubble(for: IntakeTurn(role: .user, content: voice.partialTranscript))
                            .opacity(0.55)
                    }
                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Coach is typing…")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: transcript.count) {
                if let last = transcript.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(for turn: IntakeTurn) -> some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 40) }
            Text(turn.content)
                .foregroundStyle(Color.appTextPrimary)
                .padding(10)
                .background(
                    turn.role == .user
                        ? AnyShapeStyle(Color.appAccent.opacity(0.22))
                        : AnyShapeStyle(Color.appSurface),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.appBorder, lineWidth: turn.role == .assistant ? 1 : 0)
                )
            if turn.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    /// Live view of what the conversation has established. Unknown fields
    /// stay dim, so it doubles as a progress indicator for the check-in.
    private var knownStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CheckInField.allCases, id: \.self) { field in
                    if let label = label(for: field) {
                        Chip(
                            label: label,
                            systemImage: symbol(for: field),
                            selected: knownFields.contains(field)
                        )
                        .accessibilityIdentifier("intakeChip-\(field.rawValue)")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .animation(.easeOut(duration: 0.2), value: knownFields)
        }
        .background(Color.appBackground)
    }

    private func label(for field: CheckInField) -> String? {
        let known = knownFields.contains(field)
        switch field {
        case .energy:
            return known ? checkIn.energy.displayName : "Energy"
        case .venue:
            return known ? checkIn.venue.displayName : "Where"
        case .minutes:
            return known ? "\(checkIn.minutesAvailable) min" : "Time"
        case .style:
            return known ? (checkIn.preferredStyle?.displayName ?? "Coach's choice") : "Style"
        case .soreness:
            // Only worth a chip once there's something to show.
            return known ? checkIn.sorenessOrPain : nil
        case .mood:
            return nil
        }
    }

    private func symbol(for field: CheckInField) -> String {
        switch field {
        case .energy: return "bolt"
        case .venue: return checkIn.venue.symbol
        case .minutes: return "clock"
        case .style: return checkIn.preferredStyle?.symbol ?? "sparkles"
        case .soreness: return "bandage"
        case .mood: return "face.smiling"
        }
    }

    // MARK: - Voice

    private var voiceControls: some View {
        VStack(spacing: 12) {
            VoiceOrb(phase: voice.phase) {
                // Tapping the orb interrupts whatever the loop is doing —
                // the one escape hatch when it mishears or won't stop.
                voice.stop()
            }
            Text(voice.phase.hint)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .contentTransition(.opacity)

            Button("Type instead") {
                voice.stop()
                voiceMode = false
            }
            .buttonStyle(.ghost)
            .accessibilityIdentifier("intakeTypeInstead")
        }
        .padding()
        .background(Color.appBackground)
    }

    /// Enters hands-free mode: greet, then hand straight over to listening.
    private func startVoiceMode() async {
        guard await voice.prepare() else {
            voiceMode = false
            errorMessage = "I need microphone and speech access to talk. You can turn them on in Settings — or just type."
            return
        }
        voiceMode = true
        // Re-speak the most recent thing the coach said, so entering voice
        // mode part-way through a typed conversation picks up in context.
        await runVoiceTurn(speaking: transcript.last(where: { $0.role == .assistant })?.content)
    }

    /// One hands-free turn: say something, listen for the answer, send it,
    /// then recurse on the reply. Recursion is safe — each turn suspends on
    /// real speech, so nothing accumulates.
    private func runVoiceTurn(speaking line: String?) async {
        guard voiceMode else { return }
        if let line { await voice.speak(line) }
        guard voiceMode else { return }

        // The coach has everything it needs, so finish the job rather than
        // asking for a tap — a tap is exactly what voice mode is avoiding.
        if isReady {
            voice.stop()
            dismiss()
            onGenerate()
            return
        }

        voice.listen { utterance in
            Task {
                let reply = await send(utterance)
                await runVoiceTurn(speaking: reply)
            }
        }
    }

    // MARK: - Typing

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 10) {
            if isReady {
                Button {
                    voice.stop()
                    dismiss()
                    onGenerate()
                } label: {
                    Label("Build my workout", systemImage: "sparkles")
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("intakeGenerate")
            }

            HStack(spacing: 8) {
                Button {
                    Task { await startVoiceMode() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                }
                .disabled(isSending)
                .accessibilityLabel("Talk to your coach")
                .accessibilityIdentifier("intakeMic")

                TextField("Tell your coach…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.appBorder, lineWidth: 1)
                    )
                    .accessibilityIdentifier("intakeInput")
                Button {
                    let text = input
                    input = ""
                    Task { _ = await send(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(isSending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("intakeSend")
            }
        }
        .padding()
        .background(Color.appBackground)
    }

    /// One turn with the coach. Returns what it said, so the voice loop can
    /// speak it; nil if the turn failed.
    @discardableResult
    private func send(_ text: String) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        isSending = true
        defer { isSending = false }

        // History as it stood before this turn — the new message is passed
        // separately, so it must not already be in the transcript.
        let history = transcript
        transcript.append(IntakeTurn(role: .user, content: trimmed))

        do {
            let reply = try await CoachService.fromSettings().intake(
                profile: profile,
                wikiContext: wikiContext,
                session: session,
                checkIn: checkIn,
                known: knownFields,
                history: history,
                userMessage: trimmed
            )
            if let patch = reply.checkIn {
                withAnimation(.easeOut(duration: 0.2)) {
                    knownFields.formUnion(checkIn.apply(patch, allowedStyles: profile.allowedStyles))
                }
            }
            transcript.append(IntakeTurn(role: .assistant, content: reply.reply))
            // Latches on: once the coach has enough, a later turn that only
            // adds colour shouldn't take the button away again.
            coachSaysReady = coachSaysReady || reply.isReadyToGenerate
            return reply.reply
        } catch {
            // Put the client's words back in the box so the turn isn't lost.
            transcript.removeLast()
            if !voiceMode { input = trimmed }
            errorMessage = error.localizedDescription
            voice.markIdle()
            return nil
        }
    }
}
