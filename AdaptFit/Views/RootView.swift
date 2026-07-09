import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first {
            TabView {
                TodayView(profile: profile)
                    .tabItem { Label("Today", systemImage: "sun.max") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "calendar") }
                SettingsView(profile: profile)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [UserProfile.self, Workout.self], inMemory: true)
}
