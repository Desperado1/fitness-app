import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    @Bindable var workout: Workout
    @State private var showFeedback = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.title)
                        .font(.title2.bold())
                    HStack(spacing: 12) {
                        Label(workout.style.displayName, systemImage: workout.style.symbol)
                        Label("\(workout.durationMinutes) min", systemImage: "clock")
                        Label(workout.intensity.displayName, systemImage: "gauge.medium")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if !workout.coachNote.isEmpty {
                    Text(workout.coachNote)
                        .font(.subheadline)
                        .italic()
                }
            }

            if !workout.warmup.isEmpty {
                Section("Warm-up") {
                    ForEach(workout.warmup, id: \.self) { step in
                        Text(step)
                    }
                }
            }

            Section("Workout") {
                ForEach(workout.blocks, id: \.self) { block in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.name)
                            .font(.headline)
                        Text("\(block.sets) × \(block.reps) · rest \(block.restSeconds)s")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let notes = block.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !workout.cooldown.isEmpty {
                Section("Cool-down") {
                    ForEach(workout.cooldown, id: \.self) { step in
                        Text(step)
                    }
                }
            }

            if !workout.safetyNote.isEmpty {
                Section("Take care") {
                    Label(workout.safetyNote, systemImage: "heart.text.square")
                        .font(.subheadline)
                }
            }

            Section {
                switch workout.status {
                case .planned:
                    Button {
                        showFeedback = true
                    } label: {
                        Label("I'm done — log how it felt", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button(role: .destructive) {
                        workout.status = .skipped
                    } label: {
                        Text("Skip today")
                            .frame(maxWidth: .infinity)
                    }
                case .completed:
                    HStack {
                        Text("Completed \(workout.feedbackEmoji ?? "✅")")
                        Spacer()
                        if let text = workout.feedbackText, !text.isEmpty {
                            Text(text)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                case .skipped:
                    Text("Skipped — see you tomorrow 💛")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(workout: workout)
                .presentationDetents([.medium])
        }
    }
}
