import SwiftUI
import SwiftData

struct TodayView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \TrainingBlock.createdAt, order: .reverse) private var blocks: [TrainingBlock]

    @AppStorage("scribeUpdateFailed") private var scribeUpdateFailed = false

    @State private var checkIn = DailyCheckIn()
    @State private var isGenerating = false
    @State private var errorMessage: String?
    /// Anchor for "today". The current date is not a reactive dependency, so
    /// without this the view would keep showing yesterday's workout after the
    /// day rolls over while the app was backgrounded. Refreshed on foreground
    /// and at midnight (see the scene-phase / day-change handlers below).
    @State private var today = Date()

    private var todaysWorkout: Workout? {
        workouts.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
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
                    checkInScreen
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .alert("Couldn't generate workout", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        // Re-anchor "today" when the app returns to the foreground and when the
        // calendar day changes while open, so a rolled-over day surfaces the
        // check-in screen instead of freezing on the previous day's workout.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date()
        }
    }

    private var checkInScreen: some View {
        Screen {
            ScreenHeader(
                title: "How are you today?",
                subtitle: Date.now.formatted(date: .complete, time: .omitted),
                showLogo: true
            )

            if scribeUpdateFailed {
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.appIconInactive)
                        Text("The coach's notes couldn't update after your last workout. You can rebuild them in Settings → Coach's Notes.")
                            .font(.footnote)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Up next")
                Card {
                    HStack(spacing: 12) {
                        IconWell(
                            systemName: activeBlock?.nextPendingSession == nil
                                ? "calendar.badge.exclamationmark"
                                : "calendar.badge.clock",
                            active: activeBlock?.nextPendingSession != nil
                        )
                        if let session = activeBlock?.nextPendingSession {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.focus)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.appTextPrimary)
                                Text("\(session.trainingStyle.displayName) · \(session.durationMinutes) min planned")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                        } else {
                            Text("No weekly plan active — plan your week in the Plan tab, or create a one-off workout below.")
                                .font(.footnote)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Energy")
                HStack(spacing: 10) {
                    ForEach(EnergyLevel.allCases) { level in
                        Button {
                            checkIn.energy = level
                        } label: {
                            OptionCard(
                                emoji: level.emoji,
                                label: level.displayName,
                                selected: checkIn.energy == level
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(level.displayName)
                        .accessibilityIdentifier("energy-\(level.rawValue)")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Where are you training?")
                PillToggle(selection: $checkIn.venue, options: [
                    (Venue.home, "Home", "house"),
                    (Venue.gym, "Gym", "building.2"),
                ])
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "How you feel")
                Card {
                    LabeledField(label: "Mood", placeholder: "How are you feeling? (optional)", text: $checkIn.moodText)
                    Rectangle().fill(Color.appBorder).frame(height: 1)
                    LabeledField(label: "Soreness or pain", placeholder: "Anything sore or hurting? (optional)", text: $checkIn.sorenessOrPain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Time available")
                Card {
                    CapsuleStepper(value: $checkIn.minutesAvailable, range: 10...120)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Style for today")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            checkIn.preferredStyle = nil
                        } label: {
                            Chip(label: "Coach's choice", systemImage: "sparkles", selected: checkIn.preferredStyle == nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("styleChip-coach")

                        ForEach(profile.allowedStyles) { style in
                            Button {
                                checkIn.preferredStyle = style
                            } label: {
                                Chip(label: style.displayName, systemImage: style.symbol, selected: checkIn.preferredStyle == style)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("styleChip-\(style.rawValue)")
                        }
                    }
                }
            }

            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Your coach is thinking…")
                    }
                } else {
                    Label(
                        activeBlock?.nextPendingSession == nil ? "Create a one-off workout" : "Create today's workout",
                        systemImage: "sparkles"
                    )
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(isGenerating)
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }

        let wiki = WikiStore(context: context)
        wiki.ensureSeeded(profile: profile)
        let session = activeBlock?.nextPendingSession

        do {
            let generated = try await CoachService.fromSettings().generateWorkout(
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
