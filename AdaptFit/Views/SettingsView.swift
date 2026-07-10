import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var profile: UserProfile

    @AppStorage("llmProvider") private var providerRaw = LLMProvider.deepseek.rawValue
    @AppStorage("llmModelOverride") private var modelOverride = ""

    @State private var apiKey = KeychainStore.read(KeychainStore.apiKeyAccount)
    @State private var keySaved = false

    private var provider: LLMProvider {
        LLMProvider(rawValue: providerRaw) ?? .deepseek
    }

    private var bannedMovementsText: Binding<String> {
        Binding(
            get: { profile.bannedMovements.joined(separator: ", ") },
            set: { newValue in
                profile.bannedMovements = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $providerRaw) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    TextField("Model (default: \(provider.defaultModel))", text: $modelOverride)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API key", text: $apiKey)
                    Button(keySaved ? "Saved ✓" : "Save API key") {
                        KeychainStore.save(apiKey, for: KeychainStore.apiKeyAccount)
                        keySaved = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            keySaved = false
                        }
                    }
                } header: {
                    Text("AI coach")
                } footer: {
                    Text("The key is stored securely in the iOS Keychain and only sent to \(provider.displayName) when generating a workout.")
                }

                Section {
                    NavigationLink {
                        WikiView(profile: profile)
                    } label: {
                        Label("Coach's Notes", systemImage: "book.closed")
                    }
                } footer: {
                    Text("What the coach remembers about your training — readable, editable, and rebuildable.")
                }

                Section("Your profile") {
                    TextField("Name", text: $profile.name)
                    TextField("Primary goal", text: $profile.primaryGoal, axis: .vertical)
                    Picker("Experience", selection: $profile.experienceRaw) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    Stepper("Sessions per week: \(profile.daysPerWeek)", value: $profile.daysPerWeek, in: 1...7)
                }

                Section("Health context") {
                    TextField("Medical notes", text: $profile.medicalNotes, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Injuries or limitations", text: $profile.injuriesOrLimitations, axis: .vertical)
                }

                Section {
                    Picker("Maximum intensity", selection: $profile.intensityCeilingRaw) {
                        ForEach(Intensity.allCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    TextField("Never program (comma-separated)", text: bannedMovementsText, axis: .vertical)
                } header: {
                    Text("Hard limits")
                } footer: {
                    Text("Enforced by the app on every generated workout and chat edit.")
                }

                Section("Equipment") {
                    TextField("At home", text: $profile.homeEquipment, axis: .vertical)
                    TextField("At the gym", text: $profile.gymEquipment, axis: .vertical)
                }

                Section("Training styles") {
                    ForEach(TrainingStyle.allCases) { style in
                        Toggle(isOn: binding(for: style)) {
                            Label(style.displayName, systemImage: style.symbol)
                        }
                    }
                }

                Section {
                    Text("AdaptFit generates workout suggestions with AI and is not a substitute for medical or professional advice. Stop any exercise that causes pain and consult your doctor about your training program.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func binding(for style: TrainingStyle) -> Binding<Bool> {
        Binding(
            get: { profile.allowedStyles.contains(style) },
            set: { isOn in
                var styles = Set(profile.allowedStyles)
                if isOn { styles.insert(style) } else { styles.remove(style) }
                // Never allow zero styles — the coach needs at least one option.
                if styles.isEmpty { styles.insert(.recovery) }
                profile.allowedStyles = TrainingStyle.allCases.filter(styles.contains)
            }
        )
    }
}
