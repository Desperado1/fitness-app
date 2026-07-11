import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    @Bindable var workout: Workout
    let profile: UserProfile

    @State private var showFeedback = false
    @State private var showChat = false

    private var isEditable: Bool { workout.status == .planned }

    var body: some View {
        Screen {
            // Hero
            Card {
                Text(workout.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.appTextPrimary)
                HStack(spacing: 6) {
                    Chip(label: workout.style.displayName, systemImage: workout.style.symbol)
                    Chip(label: "\(workout.durationMinutes) min", systemImage: "clock")
                    Chip(label: workout.intensity.displayName, systemImage: "gauge.medium")
                    Chip(label: workout.venue.displayName, systemImage: workout.venue.symbol)
                }
                if !workout.coachNote.isEmpty {
                    Text(workout.coachNote)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(Color.appTextSecondary)
                }
            }

            if !workout.warmup.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Warm-up")
                    Card {
                        ForEach(workout.warmup, id: \.self) { step in
                            bulletRow(step)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Workout")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach($workout.exercises) { $exercise in
                            ExerciseRowView(
                                exercise: $exercise,
                                styleSymbol: workout.style.symbol,
                                editable: isEditable
                            )
                            if exercise.id != workout.exercises.last?.id {
                                Rectangle()
                                    .fill(Color.appBorder)
                                    .frame(height: 1)
                                    .padding(.leading, 66)
                            }
                        }
                    }
                }
                if isEditable {
                    Text("Everything counts as done as prescribed — tap an exercise to adjust or skip it.")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }

            if !workout.cooldown.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Cool-down")
                    Card {
                        ForEach(workout.cooldown, id: \.self) { step in
                            bulletRow(step)
                        }
                    }
                }
            }

            if !workout.safetyNote.isEmpty {
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "heart.text.square")
                            .foregroundStyle(Color.appIconInactive)
                        Text(workout.safetyNote)
                            .font(.footnote)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }

            switch workout.status {
            case .planned:
                VStack(spacing: 4) {
                    Button {
                        showFeedback = true
                    } label: {
                        Label("I'm done — log how it felt", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.primaryAction)

                    Button("Skip today") {
                        workout.status = .skipped
                    }
                    .buttonStyle(.ghost)
                }
            case .completed:
                Card {
                    HStack {
                        Text("Completed \(workout.feedbackEmoji ?? "✅")")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        Spacer()
                        if let text = workout.feedbackText, !text.isEmpty {
                            Text(text)
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            case .skipped:
                Card {
                    Text("Skipped — see you tomorrow 💛")
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
        }
        .navigationTitle("Today's workout")
        .navigationBarTitleDisplayMode(.inline)
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

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Color.appIconInactive)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.appTextPrimary)
        }
    }
}

/// One exercise row: icon well, prescription, actuals, status glyph.
/// Tap opens the adjust sheet (which also handles skip/unskip).
private struct ExerciseRowView: View {
    @Binding var exercise: ExerciseResult
    let styleSymbol: String
    let editable: Bool

    @State private var showAdjust = false

    var body: some View {
        Button {
            if editable { showAdjust = true }
        } label: {
            HStack(spacing: 12) {
                IconWell(systemName: styleSymbol, active: exercise.status == .adjusted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appTextPrimary)
                        .strikethrough(exercise.status == .skipped)
                    Text("\(exercise.prescribedSets) × \(exercise.prescribedReps)\(exercise.prescribedWeight.map { " @ \($0)" } ?? "") · rest \(exercise.restSeconds)s")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .strikethrough(exercise.status == .skipped)
                    if let notes = exercise.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    if exercise.status == .adjusted {
                        Text("Did: \(exercise.actualSets ?? exercise.prescribedSets) × \(exercise.actualReps ?? exercise.prescribedReps)\((exercise.actualWeight ?? exercise.prescribedWeight).map { " @ \($0)" } ?? "")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.appAccent)
                    }
                    if let note = exercise.resultNote, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                Spacer()
                statusBadge
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showAdjust) {
            AdjustExerciseSheet(exercise: $exercise)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch exercise.status {
        case .asPrescribed:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.appIconInactive)
        case .adjusted:
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(Color.appAccent)
        case .skipped:
            Image(systemName: "xmark.circle")
                .foregroundStyle(Color.appIconInactive)
        }
    }
}

/// Log what was actually done for one exercise (or skip it).
private struct AdjustExerciseSheet: View {
    @Binding var exercise: ExerciseResult
    @Environment(\.dismiss) private var dismiss

    @State private var sets: Int = 0
    @State private var reps: String = ""
    @State private var weight: String = ""
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "What you actually did")
                    Card {
                        CapsuleStepper(value: $sets, range: 0...20, step: 1, unit: "sets")
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Reps", placeholder: "e.g. 8-10, 30 sec", text: $reps)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Weight", placeholder: "e.g. 10 kg, bodyweight", text: $weight)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Note for your coach")
                    Card {
                        LabeledField(label: "Note", placeholder: "e.g. last set was a grind, wrists ached", text: $note)
                    }
                }

                Button(exercise.status == .skipped ? "Unskip this exercise" : "Skip this exercise") {
                    if exercise.status == .skipped {
                        exercise.status = .asPrescribed
                        exercise.resultNote = nil
                    } else {
                        exercise.status = .skipped
                        exercise.resultNote = note.isEmpty ? nil : note
                    }
                    dismiss()
                }
                .buttonStyle(.ghost)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndClose() }
                }
            }
            .onAppear {
                sets = exercise.actualSets ?? exercise.prescribedSets
                reps = exercise.actualReps ?? exercise.prescribedReps
                weight = exercise.actualWeight ?? exercise.prescribedWeight ?? ""
                note = exercise.resultNote ?? ""
            }
        }
    }

    private func saveAndClose() {
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
}
