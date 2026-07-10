import SwiftUI
import SwiftData

struct PlanView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingBlock.createdAt, order: .reverse) private var blocks: [TrainingBlock]

    @State private var isPlanning = false
    @State private var showReplaceConfirmation = false
    @State private var errorMessage: String?

    private var activeBlock: TrainingBlock? {
        blocks.first { $0.status == .active }
    }

    var body: some View {
        NavigationStack {
            List {
                if let block = activeBlock {
                    Section {
                        Text(block.rationale)
                            .font(.subheadline)
                            .italic()
                    } header: {
                        Text("This week's plan")
                    } footer: {
                        Text("Started \(block.startDate.formatted(date: .abbreviated, time: .omitted)) · \(block.completedSessionIndices.count)/\(block.sessions.count) sessions done")
                    }

                    Section("Sessions") {
                        ForEach(block.sessions) { session in
                            sessionRow(session, done: block.completedSessionIndices.contains(session.index))
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "No plan yet",
                            systemImage: "calendar.badge.plus",
                            description: Text("Ask your coach to plan the week — each day's check-in then adapts the planned session to how you feel.")
                        )
                    }
                }

                Section {
                    Button {
                        if activeBlock != nil {
                            showReplaceConfirmation = true
                        } else {
                            Task { await planWeek() }
                        }
                    } label: {
                        if isPlanning {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Planning your week…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Plan my week", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isPlanning)
                }
            }
            .navigationTitle("Plan")
            .confirmationDialog(
                "Replace the current week's plan?",
                isPresented: $showReplaceConfirmation,
                titleVisibility: .visible
            ) {
                Button("Plan a new week", role: .destructive) {
                    Task { await planWeek() }
                }
            } message: {
                Text("The current block will be closed and a fresh week planned from your latest progress.")
            }
            .alert("Couldn't plan the week", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func sessionRow(_ session: PlannedSession, done: Bool) -> some View {
        DisclosureGroup {
            if let note = session.homeAlternativeNote, !note.isEmpty {
                Label(note, systemImage: "house")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(session.exercises, id: \.self) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.subheadline)
                    Text("\(exercise.sets)×\(exercise.reps)\(exercise.weight.map { " @ \($0)" } ?? "") · rest \(exercise.restSeconds)s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : session.trainingStyle.symbol)
                    .foregroundStyle(done ? .green : .accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.focus)
                        .font(.headline)
                    Text("\(session.trainingStyle.displayName) · \(session.durationMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func planWeek() async {
        isPlanning = true
        defer { isPlanning = false }

        let wiki = WikiStore(context: context)
        wiki.ensureSeeded(profile: profile)
        let previous = blocks.first

        do {
            let generated = try await CoachService(client: .fromSettings()).planBlock(
                profile: profile,
                wikiContext: wiki.contextString(),
                lastBlockSummary: previous?.summary
            )
            if let old = activeBlock {
                old.status = .abandoned
            }
            context.insert(TrainingBlock(startDate: .now, generated: generated))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
