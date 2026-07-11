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
                    Screen {
                        ScreenHeader(title: "History", subtitle: "Every session, remembered")
                        Card {
                            VStack(spacing: 10) {
                                IconWell(systemName: "figure.walk", size: 52)
                                Text("No workouts yet")
                                    .font(.headline)
                                    .foregroundStyle(Color.appTextPrimary)
                                Text("Your completed workouts will show up here — the start of your future dashboard.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                    }
                } else {
                    // A List keeps swipe-to-delete; rows are styled as cards.
                    List {
                        ScreenHeader(title: "History", subtitle: "Every session, remembered")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: Theme.screenPadding, bottom: 8, trailing: Theme.screenPadding))

                        ForEach(workouts) { workout in
                            ZStack {
                                NavigationLink {
                                    WorkoutDetailView(workout: workout, profile: profile)
                                } label: {
                                    EmptyView()
                                }
                                .opacity(0)
                                row(for: workout)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: Theme.screenPadding, bottom: 5, trailing: Theme.screenPadding))
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                context.delete(workouts[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.appBackground.ignoresSafeArea())
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func row(for workout: Workout) -> some View {
        Card {
            HStack(spacing: 12) {
                IconWell(systemName: workout.style.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appTextPrimary)
                        .lineLimit(1)
                    Text(workout.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                switch workout.status {
                case .completed:
                    Text(workout.feedbackEmoji ?? "✅")
                case .skipped:
                    Text("—").foregroundStyle(Color.appTextSecondary)
                case .planned:
                    Image(systemName: "circle.dashed").foregroundStyle(Color.appIconInactive)
                }
            }
        }
    }
}
