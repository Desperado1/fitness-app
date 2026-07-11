import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var primaryGoal = ""
    @State private var medicalNotes = ""
    @State private var injuries = ""
    @State private var homeEquipment = ""
    @State private var gymEquipment = ""
    @State private var experience: ExperienceLevel = .beginner
    @State private var daysPerWeek = 3
    @State private var selectedStyles: Set<TrainingStyle> = Set(TrainingStyle.allCases)
    @State private var bannedMovementsText = ""
    @State private var intensityCeiling: Intensity = .high

    private let styleColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Screen {
                VStack(spacing: 12) {
                    LogoMark(size: 76)
                    Text("Welcome to FlowFit")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color.appTextPrimary)
                    Text("Tell your coach a little about you. Everything stays on your phone — it's only shared with the AI when generating a workout.")
                        .font(.footnote)
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "About you")
                    Card {
                        LabeledField(label: "Name", placeholder: "Name", text: $name)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Primary goal", placeholder: "e.g. rebuild strength, lose fat", text: $primaryGoal)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Experience")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            PillToggle(selection: $experience, options: ExperienceLevel.allCases.map {
                                (value: $0, label: $0.displayName, icon: nil)
                            })
                        }
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sessions per week")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            CapsuleStepper(value: $daysPerWeek, range: 1...7, step: 1, unit: "days")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Health context")
                    Card {
                        LabeledField(label: "Medical notes", placeholder: "e.g. 10 months postpartum, PCOD, mild thyroid issue", text: $medicalNotes)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Injuries or movements to avoid", placeholder: "e.g. old knee injury (optional)", text: $injuries)
                    }
                    Text("The coach uses this to keep every workout safe and appropriate. FlowFit is not medical advice — check with your doctor before starting a new program.")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Hard limits")
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maximum intensity")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            PillToggle(selection: $intensityCeiling, options: Intensity.allCases.map {
                                (value: $0, label: $0.displayName, icon: nil)
                            })
                        }
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Never program", placeholder: "comma-separated, e.g. box jump, crunch", text: $bannedMovementsText)
                    }
                    Text("These are enforced by the app itself, on every workout, no matter what the AI suggests.")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Equipment")
                    Card {
                        LabeledField(label: "At home", placeholder: "e.g. dumbbells, band, mat", text: $homeEquipment)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "At the gym", placeholder: "e.g. full gym, or leave empty", text: $gymEquipment)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Training styles you're open to")
                    LazyVGrid(columns: styleColumns, spacing: 8) {
                        ForEach(TrainingStyle.allCases) { style in
                            Button {
                                if selectedStyles.contains(style) {
                                    selectedStyles.remove(style)
                                } else {
                                    selectedStyles.insert(style)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: style.symbol).font(.caption)
                                    Text(style.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    selectedStyles.contains(style) ? Color.appAccent : Color.appSurface,
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(Color.appBorder, lineWidth: selectedStyles.contains(style) ? 0 : 1))
                                .foregroundStyle(selectedStyles.contains(style) ? Color.appBackground : Color.appTextSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("style-\(style.rawValue)")
                        }
                    }
                }

                Button("Start training") { save() }
                    .buttonStyle(.primaryAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedStyles.isEmpty)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func save() {
        let banned = bannedMovementsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let profile = UserProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            primaryGoal: primaryGoal,
            medicalNotes: medicalNotes,
            injuriesOrLimitations: injuries,
            homeEquipment: homeEquipment,
            gymEquipment: gymEquipment,
            allowedStyles: TrainingStyle.allCases.filter(selectedStyles.contains),
            experience: experience,
            daysPerWeek: daysPerWeek,
            bannedMovements: banned,
            intensityCeiling: intensityCeiling
        )
        context.insert(profile)
    }
}

#Preview {
    OnboardingView()
        .modelContainer(
            for: [UserProfile.self, Workout.self, TrainingBlock.self, WikiPage.self, CoachChatMessage.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
