import SwiftUI
import SwiftData

@main
struct AdaptFitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [UserProfile.self, Workout.self])
    }
}
