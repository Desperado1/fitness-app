import SwiftUI
import SwiftData

/// Post-workout check-in. The rating and note are fed back into the
/// prompt for the next workout, closing the adaptation loop.
struct FeedbackSheet: View {
    @Bindable var workout: Workout
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 3
    @State private var note = ""

    private let labels = [1: "Awful", 2: "Rough", 3: "Okay", 4: "Good", 5: "Great"]

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

                Section {
                    TextField("Anything to tell your coach? (too easy, knees hurt, loved it…)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("Your coach reads this when planning your next workout.")
                }

                Section {
                    Button("Save") {
                        workout.status = .completed
                        workout.feedbackRating = rating
                        workout.feedbackText = note
                        workout.completedAt = .now
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Nice work!")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
