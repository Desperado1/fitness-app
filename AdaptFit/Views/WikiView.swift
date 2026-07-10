import SwiftUI
import SwiftData

/// "Coach's Notes": the LLM-maintained wiki, visible and editable.
/// Reading it shows what the coach believes; editing it corrects the coach.
struct WikiView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.date) private var workouts: [Workout]

    @State private var isRebuilding = false
    @State private var showRebuildConfirmation = false
    @State private var errorMessage: String?
    @State private var rebuiltAt: Date?

    private var wiki: WikiStore { WikiStore(context: context) }

    var body: some View {
        List {
            Section {
                Text("Your coach keeps these notes and reads them before every plan, workout, and chat. Edit anything that's wrong — the coach will follow your version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Pages") {
                ForEach(wiki.allPages()) { page in
                    NavigationLink {
                        WikiPageEditor(page: page, store: wiki)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(WikiSlug(rawValue: page.slug)?.title ?? page.slug)
                                .font(.headline)
                            Text("Updated \(page.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button {
                    showRebuildConfirmation = true
                } label: {
                    if isRebuilding {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Rebuilding from history…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Rebuild from history", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isRebuilding)
            } footer: {
                if let rebuiltAt {
                    Text("Rebuilt \(rebuiltAt.formatted(date: .omitted, time: .shortened)). Previous versions are kept in each page's history.")
                } else {
                    Text("Regenerates every page from your raw workout log. Use this if the notes have drifted or bloated — your workout history itself is never touched.")
                }
            }
        }
        .navigationTitle("Coach's Notes")
        .confirmationDialog(
            "Rebuild all pages from workout history?",
            isPresented: $showRebuildConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rebuild", role: .destructive) {
                Task { await rebuild() }
            }
        } message: {
            Text("Current page contents are snapshotted first, so you can restore them.")
        }
        .alert("Rebuild failed", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func rebuild() async {
        isRebuilding = true
        defer { isRebuilding = false }

        wiki.ensureSeeded(profile: profile)
        do {
            let pages = try await CoachService.fromSettings().rebuildWiki(
                profile: profile,
                historyLines: workouts.map(\.historyLine)
            )
            wiki.apply(updates: pages)
            rebuiltAt = .now
            UserDefaults.standard.set(false, forKey: "scribeUpdateFailed")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WikiPageEditor: View {
    @Bindable var page: WikiPage
    let store: WikiStore

    @State private var contentOnAppear = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $page.content)
                    .font(.body.monospaced())
                    .frame(minHeight: 260)
                    .autocorrectionDisabled()
            } footer: {
                if let slug = WikiSlug(rawValue: page.slug) {
                    Text(slug.purpose)
                }
            }

            if !page.snapshots.isEmpty {
                Section("Previous versions") {
                    ForEach(Array(page.snapshots.enumerated()), id: \.offset) { _, snapshot in
                        Button {
                            store.restore(page: page, snapshot: snapshot)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Restore version from \(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                Text(snapshot.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(WikiSlug(rawValue: page.slug)?.title ?? page.slug)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            contentOnAppear = page.content
        }
        .onDisappear {
            if page.content != contentOnAppear {
                page.updatedAt = .now
            }
        }
    }
}
