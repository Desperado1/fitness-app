import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    @Bindable var workout: Workout
    let profile: UserProfile

    @State private var showFeedback = false
    @State private var showChat = false

    private var isEditable: Bool { workout.status == .planned }

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
                        Label(workout.venue.displayName, systemImage: workout.venue.symbol)
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

            Section {
                ForEach($workout.exercises) { $exercise in
                    ExerciseRow(exercise: $exercise, editable: isEditable)
                }
            } header: {
                Text("Workout")
            } footer: {
                if isEditable {
                    Text("Everything counts as done as prescribed unless you adjust or skip it.")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showChat = true
                } label: {
                    Label("Chat with coach", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(workout: workout)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChat) {
            ChatView(workout: workout, profile: profile)
        }
    }
}

/// One exercise: prescription, actual-vs-prescribed status, adjust/skip controls.
private struct ExerciseRow: View {
    @Binding var exercise: ExerciseResult
    let editable: Bool

    @State private var showAdjust = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(exercise.name)
                    .font(.headline)
                Spacer()
                statusBadge
            }
            Text("\(exercise.prescribedSets) × \(exercise.prescribedReps)\(exercise.prescribedWeight.map { " @ \($0)" } ?? "") · rest \(exercise.restSeconds)s")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .strikethrough(exercise.status == .skipped)
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if exercise.status == .adjusted {
                Text("Did: \(exercise.actualSets ?? exercise.prescribedSets) × \(exercise.actualReps ?? exercise.prescribedReps)\((exercise.actualWeight ?? exercise.prescribedWeight).map { " @ \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let note = exercise.resultNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if editable {
                if exercise.status == .skipped {
                    Button("Unskip") {
                        exercise.status = .asPrescribed
                        exercise.resultNote = nil
                    }
                    .tint(.green)
                } else {
                    Button("Skip") { exercise.status = .skipped }
                        .tint(.red)
                    Button("Adjust") { showAdjust = true }
                        .tint(.orange)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editable && exercise.status != .skipped {
                showAdjust = true
            }
        }
        .sheet(isPresented: $showAdjust) {
            AdjustExerciseSheet(exercise: $exercise)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch exercise.status {
        case .asPrescribed:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
        case .adjusted:
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.orange)
        case .skipped:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.red)
        }
    }
}

/// Log what was actually done for one exercise.
private struct AdjustExerciseSheet: View {
    @Binding var exercise: ExerciseResult
    @Environment(\.dismiss) private var dismiss

    @State private var sets: Int = 0
    @State private var reps: String = ""
    @State private var weight: String = ""
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What you actually did") {
                    Stepper("Sets: \(sets)", value: $sets, in: 0...20)
                    TextField("Reps (e.g. 8-10, 30 sec)", text: $reps)
                    TextField("Weight (e.g. 10 kg, bodyweight)", text: $weight)
                }
                Section("Note for your coach") {
                    TextField("e.g. last set was a grind, wrists ached", text: $note, axis: .vertical)
                }
                Section {
                    Button("Save") {
                        exercise.actualSets = sets
                        exercise.actualReps = reps
                        exercise.actualWeight = weight.isEmpty ? nil : weight
                        exercise.resultNote = note.isEmpty ? nil : note
                        let unchanged = sets == exercise.prescribedSets
                            && reps == exercise.prescribedReps
                            && (weight.isEmpty ? exercise.prescribedWeight == nil : weight == exercise.prescribedWeight)
                        exercise.status = unchanged ? .asPrescribed : .adjusted
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                sets = exercise.actualSets ?? exercise.prescribedSets
                reps = exercise.actualReps ?? exercise.prescribedReps
                weight = exercise.actualWeight ?? exercise.prescribedWeight ?? ""
                note = exercise.resultNote ?? ""
            }
        }
    }
}
