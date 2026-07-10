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
                                    .foregroundStyle(.secondary)
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
                                        .foregroundStyle(.secondary)
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

                Divider()

                HStack(spacing: 8) {
                    TextField("Message your coach…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(isSending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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
                .padding(10)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(.tint.opacity(0.2))
                        : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 14)
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
            let reply = try await CoachService(client: .fromSettings()).chat(
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
