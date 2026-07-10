import SwiftUI
import SwiftData

struct TodayView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \TrainingBlock.createdAt, order: .reverse) private var blocks: [TrainingBlock]

    @AppStorage("scribeUpdateFailed") private var scribeUpdateFailed = false

    @State private var checkIn = DailyCheckIn()
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var todaysWorkout: Workout? {
        workouts.first { Calendar.current.isDateInToday($0.date) }
    }

    private var activeBlock: TrainingBlock? {
        blocks.first { $0.status == .active }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = todaysWorkout {
                    WorkoutDetailView(workout: workout, profile: profile)
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
            if scribeUpdateFailed {
                Section {
                    Label(
                        "The coach's notes couldn't update after your last workout. You can rebuild them in Settings → Coach's Notes.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                if let session = activeBlock?.nextPendingSession {
                    Label(session.summaryLine, systemImage: "calendar.badge.clock")
                        .font(.subheadline)
                } else {
                    Label(
                        "No weekly plan active — plan your week in the Plan tab, or create a one-off workout below.",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Up next")
            }

            Section("Energy") {
                Picker("Energy", selection: $checkIn.energy) {
                    ForEach(EnergyLevel.allCases) { level in
                        Text("\(level.emoji) \(level.displayName)").tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Where are you training?") {
                Picker("Venue", selection: $checkIn.venue) {
                    ForEach(Venue.allCases) { venue in
                        Label(venue.displayName, systemImage: venue.symbol).tag(venue)
                    }
                }
                .pickerStyle(.segmented)
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
                        Label(
                            activeBlock?.nextPendingSession == nil ? "Create a one-off workout" : "Create today's workout",
                            systemImage: "sparkles"
                        )
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

        let wiki = WikiStore(context: context)
        wiki.ensureSeeded(profile: profile)
        let session = activeBlock?.nextPendingSession

        do {
            let generated = try await CoachService(client: .fromSettings()).generateWorkout(
                profile: profile,
                wikiContext: wiki.contextString(),
                session: session,
                checkIn: checkIn
            )
            context.insert(Workout(
                date: .now,
                generated: generated,
                checkIn: checkIn,
                blockSessionIndex: session?.index
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
