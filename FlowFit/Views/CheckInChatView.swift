import SwiftUI

/// The typed conversational check-in: instead of tapping energy, venue,
/// time and style, the client writes and the coach fills them in. The chips
/// under the thread show what it has heard, so a misheard answer is visible
/// immediately and correctable by hand — the form on TodayView stays the
/// source of truth.
///
/// Typing only. Voice lives on `VoiceCheckInView`, which is the whole
/// screen rather than a control inside a sheet — a mic button in a composer
/// is what made voice feel like dictation in the first place.
struct CheckInChatView: View {
    @ObservedObject var conversation: IntakeConversation

    /// Called when the client accepts the coach's hand-off. TodayView owns
    /// workout generation, so this view never runs the modulator itself.
    let onGenerate: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                thread
                Rectangle().fill(Color.appBorder).frame(height: 1)
                KnownFieldsStrip(
                    checkIn: conversation.checkIn,
                    knownFields: conversation.knownFields
                )
                .background(Color.appBackground)
                composer
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Your coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Adjust by hand") { dismiss() }
                        .accessibilityIdentifier("intakeAdjustByHand")
                }
            }
            .alert("Couldn't reach your coach", isPresented: .init(
                get: { conversation.errorMessage != nil },
                set: { if !$0 { conversation.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text((conversation.errorMessage ?? "") + "\n\nYou can still fill in the check-in by hand.")
            }
        }
        .task { conversation.startIfNeeded() }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(conversation.transcript) { turn in
                        bubble(for: turn).id(turn.id)
                    }
                    if conversation.isSending {
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
            .onChange(of: conversation.transcript.count) {
                if let last = conversation.transcript.last {
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

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 10) {
            if conversation.isReady {
                Button {
                    dismiss()
                    onGenerate()
                } label: {
                    Label("Build my workout", systemImage: "sparkles")
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("intakeGenerate")
            }

            HStack(spacing: 8) {
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
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(conversation.isSending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("intakeSend")
            }
        }
        .padding()
        .background(Color.appBackground)
    }

    private func send() async {
        let text = input
        input = ""
        if await conversation.send(text) == nil {
            // Put the client's words back in the box so the turn isn't lost.
            input = text
        }
    }
}
