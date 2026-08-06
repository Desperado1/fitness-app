import SwiftUI
import SwiftData

/// Per-workout chat with the coach. The coach can answer questions and
/// apply structured edits to today's workout; transcripts are stored as
/// raw data for wiki rebuilds.
struct ChatView: View {
    let workout: Workout
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var messages: [CoachChatMessage]

    @AppStorage("speakCoachReplies") private var speakCoachReplies = true
    @StateObject private var voice = VoiceSession()

    @State private var input = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    init(workout: Workout, profile: UserProfile) {
        self.workout = workout
        self.profile = profile
        let workoutUUID = workout.uuid
        _messages = Query(
            filter: #Predicate<CoachChatMessage> { $0.workoutUUID == workoutUUID },
            sort: \CoachChatMessage.date
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if messages.isEmpty {
                                Text("Ask about today's workout or request a change — \"my wrists hurt, swap the push-ups\", \"make it shorter\", \"why deadlifts today?\"")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .padding()
                            }
                            ForEach(messages) { message in
                                bubble(for: message)
                                    .id(message.persistentModelID)
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
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.persistentModelID, anchor: .bottom)
                            }
                        }
                    }
                }

                Rectangle()
                    .fill(Color.appBorder)
                    .frame(height: 1)

                HStack(spacing: 8) {
                    // Dictation rather than the full hands-free loop: in a
                    // chat you're usually looking at the screen anyway, and
                    // seeing the text before it sends is worth the tap.
                    Button {
                        if voice.isListening {
                            voice.stopListening()
                        } else {
                            Task {
                                guard await voice.prepare() else { return }
                                voice.listen { text in
                                    input = text
                                    voice.markIdle()
                                }
                            }
                        }
                    } label: {
                        Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                            .font(.title3)
                            .foregroundStyle(voice.isListening ? Color.appAccent : Color.appTextSecondary)
                    }
                    .disabled(isSending)
                    .accessibilityLabel("Dictate a message")
                    .accessibilityIdentifier("chatMic")

                    TextField("Message your coach…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                        .accessibilityIdentifier("chatInput")
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(isSending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("chatSend")
                }
                .padding()
                .background(Color.appBackground)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        voice.stop()
                        dismiss()
                    }
                }
            }
            .onDisappear { voice.stop() }
            .alert("Message failed", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func bubble(for message: CoachChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .foregroundStyle(Color.appTextPrimary)
                .padding(10)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(Color.appAccent.opacity(0.22))
                        : AnyShapeStyle(Color.appSurface),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.appBorder, lineWidth: message.role == .assistant ? 1 : 0)
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        let wiki = WikiStore(context: context)
        do {
            let reply = try await CoachService.fromSettings().chat(
                profile: profile,
                wikiContext: wiki.contextString(),
                workout: workout,
                history: messages,
                userMessage: text
            )
            context.insert(CoachChatMessage(workoutUUID: workout.uuid, role: .user, content: text))
            var assistantText = reply.reply
            if let updated = reply.updatedWorkout {
                workout.apply(updated)
                assistantText += "\n\n✔︎ I've updated today's workout."
            }
            context.insert(CoachChatMessage(workoutUUID: workout.uuid, role: .assistant, content: assistantText))
            input = ""

            if speakCoachReplies {
                // Speak the coach's own words only — the appended edit
                // confirmation is a UI marker, not something to read out.
                // Not awaited, so the reply is readable and the next message
                // typeable while it's still talking.
                let spoken = reply.reply
                Task { await voice.speak(spoken) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
