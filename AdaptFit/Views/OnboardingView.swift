import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var primaryGoal = ""
    @State private var medicalNotes = ""
    @State private var injuries = ""
    @State private var equipment = ""
    @State private var experience: ExperienceLevel = .beginner
    @State private var daysPerWeek = 3
    @State private var selectedStyles: Set<TrainingStyle> = Set(TrainingStyle.allCases)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell your coach a little about you. Everything stays on your phone — it's only shared with the AI when generating a workout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("About you") {
                    TextField("Name", text: $name)
                    TextField("Primary goal (e.g. rebuild strength, lose fat)", text: $primaryGoal, axis: .vertical)
                    Picker("Experience", selection: $experience) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Stepper("Sessions per week: \(daysPerWeek)", value: $daysPerWeek, in: 1...7)
                }

                Section {
                    TextField("e.g. 10 months postpartum, PCOD, mild thyroid issue", text: $medicalNotes, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Injuries or movements to avoid", text: $injuries, axis: .vertical)
                } header: {
                    Text("Health context")
                } footer: {
                    Text("The coach uses this to keep every workout safe and appropriate. AdaptFit is not medical advice — check with your doctor before starting a new program.")
                }

                Section("Equipment you have") {
                    TextField("e.g. pair of dumbbells, resistance band, yoga mat", text: $equipment, axis: .vertical)
                }

                Section("Training styles you're open to") {
                    ForEach(TrainingStyle.allCases) { style in
                        Toggle(isOn: binding(for: style)) {
                            Label(style.displayName, systemImage: style.symbol)
                        }
                    }
                }

                Section {
                    Button("Start training") { save() }
                        .frame(maxWidth: .infinity)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedStyles.isEmpty)
                }
            }
            .navigationTitle("Welcome to AdaptFit")
        }
    }

    private func binding(for style: TrainingStyle) -> Binding<Bool> {
        Binding(
            get: { selectedStyles.contains(style) },
            set: { isOn in
                if isOn { selectedStyles.insert(style) } else { selectedStyles.remove(style) }
            }
        )
    }

    private func save() {
        let profile = UserProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            primaryGoal: primaryGoal,
            medicalNotes: medicalNotes,
            injuriesOrLimitations: injuries,
            equipment: equipment,
            allowedStyles: TrainingStyle.allCases.filter(selectedStyles.contains),
            experience: experience,
            daysPerWeek: daysPerWeek
        )
        context.insert(profile)
    }
}

#Preview {
    OnboardingView()
        .modelContainer(for: [UserProfile.self, Workout.self], inMemory: true)
}
