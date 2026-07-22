import SwiftUI
import SwiftData

/// Post-workout check-in. The rating, note, and actuals feed the wiki
/// scribe and the next plan, closing the adaptation loop.
struct FeedbackSheet: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("scribeUpdateFailed") private var scribeUpdateFailed = false

    @State private var rating = 3
    @State private var note = ""
    @State private var actualMinutes: Int

    private let labels = [1: "Awful", 2: "Rough", 3: "Okay", 4: "Good", 5: "Great"]

    init(workout: Workout) {
        self.workout = workout
        _actualMinutes = State(initialValue: workout.durationMinutes)
    }

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "How did it feel?")
                    Card {
                        HStack {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) { rating = value }
                                } label: {
                                    Image(systemName: value <= rating ? "star.fill" : "star")
                                        .font(.title)
                                        .foregroundStyle(value <= rating ? Color.appAccent : Color.appIconInactive)
                                        .scaleEffect(value == rating ? 1.15 : 1)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .sensoryFeedback(.selection, trigger: rating)
                        Text(labels[rating] ?? "")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                            .contentTransition(.opacity)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "How long did it take?")
                    Card {
                        CapsuleStepper(value: $actualMinutes, range: 5...180)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Tell your coach")
                    Card {
                        LabeledField(
                            label: "Anything worth knowing?",
                            placeholder: "too easy, knees hurt, loved it… (optional)",
                            text: $note
                        )
                    }
                    Text("Your coach reads this — and what you adjusted or skipped — when planning what's next.")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }

                Button("Save") { save() }
                    .buttonStyle(.primaryAction)
            }
            .navigationTitle("Nice work!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Always reachable even at the half-height detent.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        workout.status = .completed
        workout.feedbackRating = rating
        workout.feedbackText = note
        workout.actualDurationMinutes = actualMinutes
        workout.completedAt = .now

        // Tick off the planned session this workout realized.
        if let sessionIndex = workout.blockSessionIndex {
            let blocks = (try? context.fetch(FetchDescriptor<TrainingBlock>())) ?? []
            if let active = blocks.first(where: { $0.status == .active }) {
                active.markSessionCompleted(sessionIndex)
            }
        }

        // Fire the wiki scribe in the background; the wiki is rebuildable,
        // so failure only sets a flag surfaced as a note in TodayView.
        let workout = self.workout
        let context = self.context
        Task { @MainActor in
            let wiki = WikiStore(context: context)
            do {
                let updates = try await CoachService.fromSettings().scribeUpdates(
                    wikiContext: wiki.contextString(),
                    workout: workout
                )
                wiki.apply(updates: updates)
                UserDefaults.standard.set(false, forKey: "scribeUpdateFailed")
            } catch {
                UserDefaults.standard.set(true, forKey: "scribeUpdateFailed")
            }
        }

        dismiss()
    }
}
