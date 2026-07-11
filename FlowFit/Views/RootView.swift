import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                TabView {
                    TodayView(profile: profile)
                        .tabItem { Label("Today", systemImage: "sun.max") }
                    PlanView(profile: profile)
                        .tabItem { Label("Plan", systemImage: "calendar.badge.clock") }
                    HistoryView(profile: profile)
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    SettingsView(profile: profile)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .task {
                    WikiStore(context: context).ensureSeeded(profile: profile)
                }
            } else {
                OnboardingView()
            }
        }
        // Dark-first design system: fixed palette, so pin the scheme.
        .preferredColorScheme(.dark)
        .tint(Color.appAccent)
    }
}

#Preview {
    RootView()
        .modelContainer(
            for: [UserProfile.self, Workout.self, TrainingBlock.self, WikiPage.self, CoachChatMessage.self],
            inMemory: true
        )
}
