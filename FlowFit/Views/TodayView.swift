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
    /// Which check-in fields have actually been established — by the
    /// conversation or by hand. Every field has a usable default, so the
    /// values alone can't tell an answer from an untouched default, and the
    /// intake coach needs that difference to know what's left to ask.
    @State private var knownFields: Set<CheckInField> = []
    @State private var intakeTranscript: [IntakeTurn] = []
    @State private var showingIntake = false
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
                    WorkoutDetailView(workout: workout, profile: profile, canRegenerate: true)
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
            .sheet(isPresented: $showingIntake) {
                CheckInChatView(
                    profile: profile,
                    session: activeBlock?.nextPendingSession,
                    // The intake coach only needs who the client is and where
                    // the week stands; progressions and the log would cost
                    // latency on every turn for nothing.
                    wikiContext: WikiStore(context: context)
                        .contextString(slugs: [.profile, .currentBlock]),
                    checkIn: $checkIn,
                    knownFields: $knownFields,
                    transcript: $intakeTranscript,
                    onGenerate: { Task { await generate() } }
                )
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

            // The conversational path. It writes into the very same check-in
            // the form below binds to, so talking and tapping are two ways
            // into one state — and a misheard answer is fixed with a tap.
            VStack(spacing: 12) {
                Button {
                    WikiStore(context: context).ensureSeeded(profile: profile)
                    showingIntake = true
                } label: {
                    Label(
                        intakeTranscript.isEmpty ? "Talk it through" : "Continue with your coach",
                        systemImage: "bubble.left.and.text.bubble.right"
                    )
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("startIntake")

                HStack(spacing: 10) {
                    Rectangle().fill(Color.appBorder).frame(height: 1)
                    Text("or fill it in yourself")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .fixedSize()
                    Rectangle().fill(Color.appBorder).frame(height: 1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Energy")
                HStack(spacing: 10) {
                    ForEach(EnergyLevel.allCases) { level in
                        Button {
                            // Marked known explicitly rather than via onChange:
                            // "steady" is the default, so tapping it first
                            // would otherwise register as no answer at all.
                            knownFields.insert(.energy)
                            withAnimation(.easeOut(duration: 0.15)) { checkIn.energy = level }
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
                .sensoryFeedback(.selection, trigger: checkIn.energy)
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
                            knownFields.insert(.style)
                            withAnimation(.easeOut(duration: 0.15)) { checkIn.preferredStyle = nil }
                        } label: {
                            Chip(label: "Coach's choice", systemImage: "sparkles", selected: checkIn.preferredStyle == nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("styleChip-coach")

                        ForEach(profile.allowedStyles) { style in
                            Button {
                                knownFields.insert(.style)
                                withAnimation(.easeOut(duration: 0.15)) { checkIn.preferredStyle = style }
                            } label: {
                                Chip(label: style.displayName, systemImage: style.symbol, selected: checkIn.preferredStyle == style)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("styleChip-\(style.rawValue)")
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: checkIn.preferredStyle)
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
        // Editing by hand counts as answering, so a later conversation
        // doesn't ask again for something already filled in on the form.
        .onChange(of: checkIn.venue) { knownFields.insert(.venue) }
        .onChange(of: checkIn.minutesAvailable) { knownFields.insert(.minutes) }
        .onChange(of: checkIn.moodText) { _, text in
            if !text.isEmpty { knownFields.insert(.mood) }
        }
        .onChange(of: checkIn.sorenessOrPain) { _, text in
            if !text.isEmpty { knownFields.insert(.soreness) }
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
            let workout = Workout(
                date: .now,
                generated: generated,
                checkIn: checkIn,
                blockSessionIndex: session?.index
            )
            context.insert(workout)

            // Carry the check-in conversation into the workout's thread now
            // that there's a UUID to key it by, so the chat coach picks up
            // mid-conversation instead of starting cold.
            for turn in intakeTranscript {
                context.insert(CoachChatMessage(
                    workoutUUID: workout.uuid,
                    role: turn.role,
                    content: turn.content
                ))
            }
            intakeTranscript.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
