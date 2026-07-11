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
                            .foregroundStyle(Color.appTextSecondary)
                    } header: {
                        Text("This week's plan")
                    } footer: {
                        Text("Started \(block.startDate.formatted(date: .abbreviated, time: .omitted)) · \(block.completedSessionIndices.count)/\(block.sessions.count) sessions done")
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .themedRow()

                    Section("Sessions") {
                        ForEach(block.sessions) { session in
                            sessionRow(session, done: block.completedSessionIndices.contains(session.index))
                        }
                    }
                    .themedRow()
                } else {
                    Section {
                        ContentUnavailableView(
                            "No plan yet",
                            systemImage: "calendar.badge.plus",
                            description: Text("Ask your coach to plan the week — each day's check-in then adapts the planned session to how you feel.")
                        )
                    }
                    .listRowBackground(Color.clear)
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
                        } else {
                            Label("Plan my week", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(isPlanning)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(24)
            .themedScreen()
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WikiView(profile: profile)
                    } label: {
                        Label("Coach's Notes", systemImage: "book.closed")
                    }
                }
            }
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
                    .foregroundStyle(Color.appTextSecondary)
            }
            ForEach(session.exercises, id: \.self) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextPrimary)
                    Text("\(exercise.sets)×\(exercise.reps)\(exercise.weight.map { " @ \($0)" } ?? "") · rest \(exercise.restSeconds)s")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : session.trainingStyle.symbol)
                    .foregroundStyle(done ? Color.appAccent : Color.appIconInactive)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.focus)
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    Text("\(session.trainingStyle.displayName) · \(session.durationMinutes) min")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
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
            let generated = try await CoachService.fromSettings().planBlock(
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
