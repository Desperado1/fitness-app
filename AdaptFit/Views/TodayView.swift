import SwiftUI
import SwiftData

struct TodayView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    @AppStorage("llmProvider") private var providerRaw = LLMProvider.deepseek.rawValue
    @AppStorage("llmModelOverride") private var modelOverride = ""

    @State private var checkIn = DailyCheckIn()
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var todaysWorkout: Workout? {
        workouts.first { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = todaysWorkout {
                    WorkoutDetailView(workout: workout)
                } else {
                    checkInForm
                }
            }
            .navigationTitle(todaysWorkout == nil ? "How are you today?" : "Today's workout")
            .alert("Couldn't generate workout", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var checkInForm: some View {
        Form {
            Section("Energy") {
                Picker("Energy", selection: $checkIn.energy) {
                    ForEach(EnergyLevel.allCases) { level in
                        Text("\(level.emoji) \(level.displayName)").tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Mood") {
                TextField("How are you feeling? (optional)", text: $checkIn.moodText, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section("Body") {
                TextField("Any soreness or pain? (optional)", text: $checkIn.sorenessOrPain, axis: .vertical)
            }

            Section("Time") {
                Stepper("\(checkIn.minutesAvailable) minutes", value: $checkIn.minutesAvailable, in: 10...120, step: 5)
            }

            Section("Style for today") {
                Picker("Style", selection: $checkIn.preferredStyle) {
                    Text("Coach's choice").tag(TrainingStyle?.none)
                    ForEach(profile.allowedStyles) { style in
                        Text(style.displayName).tag(TrainingStyle?.some(style))
                    }
                }
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Your coach is thinking…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Create my workout", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isGenerating)
            }
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }

        let provider = LLMProvider(rawValue: providerRaw) ?? .deepseek
        let client = LLMClient(
            provider: provider,
            modelOverride: modelOverride,
            apiKey: KeychainStore.read(KeychainStore.apiKeyAccount)
        )
        do {
            let generated = try await WorkoutGenerator(client: client).generate(
                profile: profile,
                checkIn: checkIn,
                recentWorkouts: Array(workouts.prefix(7))
            )
            context.insert(Workout(date: .now, generated: generated, checkIn: checkIn))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
