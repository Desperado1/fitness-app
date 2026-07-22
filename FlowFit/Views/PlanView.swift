import SwiftUI
import SwiftData

/// How a planned session reads in the Plan list: still to do, done, or skipped.
enum PlannedSessionState {
    case pending, done, skipped

    /// Overrides the session's style symbol; nil keeps the style icon.
    var iconName: String? {
        switch self {
        case .pending: return nil
        case .done: return "checkmark"
        case .skipped: return "xmark"
        }
    }
}

struct PlanView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingBlock.createdAt, order: .reverse) private var blocks: [TrainingBlock]

    @State private var isPlanning = false
    @State private var showReplaceConfirmation = false
    @State private var errorMessage: String?
    @State private var expandedSessions: Set<Int> = []

    private var activeBlock: TrainingBlock? {
        blocks.first { $0.status == .active }
    }

    var body: some View {
        NavigationStack {
            Screen {
                HStack(alignment: .center) {
                    ScreenHeader(title: "Plan", subtitle: "Your training week")
                    NavigationLink {
                        WikiView(profile: profile)
                    } label: {
                        IconWell(systemName: "book.closed")
                    }
                    .accessibilityLabel("Coach's Notes")
                }

                if let block = activeBlock {
                    Card {
                        Text(block.rationale)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(Color.appTextSecondary)
                        ThinProgressBar(
                            progress: block.sessions.isEmpty
                                ? 0
                                : Double(block.resolvedSessionCount) / Double(block.sessions.count)
                        )
                        HStack {
                            Text("Started \(block.startDate.formatted(date: .abbreviated, time: .omitted))")
                            Spacer()
                            Text(block.skippedSessionIndices.isEmpty
                                ? "\(block.completedSessionIndices.count)/\(block.sessions.count) done"
                                : "\(block.completedSessionIndices.count) done · \(block.skippedSessionIndices.count) skipped")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Sessions")
                        ForEach(block.sessions) { session in
                            let state: PlannedSessionState = block.completedSessionIndices.contains(session.index)
                                ? .done
                                : block.skippedSessionIndices.contains(session.index) ? .skipped : .pending
                            sessionCard(session, state: state)
                        }
                    }
                } else {
                    Card {
                        VStack(spacing: 10) {
                            IconWell(systemName: "calendar.badge.plus", size: 52)
                            Text("No plan yet")
                                .font(.headline)
                                .foregroundStyle(Color.appTextPrimary)
                            Text("Ask your coach to plan the week — each day's check-in then adapts the planned session to how you feel.")
                                .font(.footnote)
                                .foregroundStyle(Color.appTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }

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
            .toolbar(.hidden, for: .navigationBar)
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

    private func sessionCard(_ session: PlannedSession, state: PlannedSessionState) -> some View {
        Card {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if expandedSessions.contains(session.index) {
                        expandedSessions.remove(session.index)
                    } else {
                        expandedSessions.insert(session.index)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    IconWell(
                        systemName: state.iconName ?? session.trainingStyle.symbol,
                        active: state == .done
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.focus)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.appTextPrimary)
                            if state == .skipped {
                                Text("Skipped")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.appTextSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.appBorder, in: Capsule())
                            }
                        }
                        Text("\(session.trainingStyle.displayName) · \(session.durationMinutes) min")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appIconInactive)
                        .rotationEffect(.degrees(expandedSessions.contains(session.index) ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedSessions.contains(session.index) {
                VStack(alignment: .leading, spacing: 8) {
                    if let note = session.homeAlternativeNote, !note.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "house")
                                .font(.caption)
                                .foregroundStyle(Color.appIconInactive)
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                    ForEach(session.exercises, id: \.self) { exercise in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.appTextPrimary)
                            Text("\(exercise.sets)×\(exercise.reps)\(exercise.weight.map { " @ \($0)" } ?? "") · rest \(exercise.restSeconds)s")
                                .font(.caption2)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                }
                .padding(.leading, 50)
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
