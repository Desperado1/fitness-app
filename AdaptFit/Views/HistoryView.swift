import SwiftUI
import SwiftData

struct HistoryView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "figure.walk",
                        description: Text("Your completed workouts will show up here — the start of your future dashboard.")
                    )
                } else {
                    List {
                        ForEach(workouts) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout, profile: profile)
                            } label: {
                                row(for: workout)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                context.delete(workouts[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func row(for workout: Workout) -> some View {
        HStack(spacing: 12) {
            Image(systemName: workout.style.symbol)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(workout.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch workout.status {
            case .completed:
                Text(workout.feedbackEmoji ?? "✅")
            case .skipped:
                Text("—").foregroundStyle(.secondary)
            case .planned:
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            }
        }
    }
}
