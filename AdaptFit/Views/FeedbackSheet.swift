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
            Form {
                Section("How did it feel?") {
                    HStack {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                rating = value
                            } label: {
                                Image(systemName: value <= rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(value <= rating ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text(labels[rating] ?? "")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }

                Section("How long did it take?") {
                    Stepper("\(actualMinutes) minutes", value: $actualMinutes, in: 5...180, step: 5)
                }

                Section {
                    TextField("Anything to tell your coach? (too easy, knees hurt, loved it…)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("Your coach reads this — and what you adjusted or skipped — when planning what's next.")
                }

                Section {
                    Button("Save") { save() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Nice work!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Always reachable even at the half-height detent, where
                // the in-form Save can sit below the fold.
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
