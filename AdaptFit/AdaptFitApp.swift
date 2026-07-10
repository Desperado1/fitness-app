import SwiftUI
import SwiftData

@main
struct AdaptFitApp: App {
    init() {
        Theme.configureAppearance()
    }

    let container: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            Workout.self,
            TrainingBlock.self,
            WikiPage.self,
            CoachChatMessage.self,
        ])
        // UI tests get a throwaway in-memory store so every run starts fresh.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
