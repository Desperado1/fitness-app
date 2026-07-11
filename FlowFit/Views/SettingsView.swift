import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var profile: UserProfile

    @AppStorage("llmProvider") private var providerRaw = LLMProvider.deepseek.rawValue
    @AppStorage("llmModelOverride") private var modelOverride = ""

    @State private var apiKey = KeychainStore.read(KeychainStore.apiKeyAccount)
    @State private var keySaved = false

    private let styleColumns = [GridItem(.flexible()), GridItem(.flexible())]

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
            Screen {
                ScreenHeader(title: "Settings", subtitle: "Coach, profile, and limits")

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "AI coach")
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Provider")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            PillToggle(selection: $providerRaw, options: LLMProvider.allCases.map {
                                (value: $0.rawValue, label: $0.displayName, icon: nil)
                            })
                        }
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Model (default: \(provider.defaultModel))", placeholder: provider.defaultModel, text: $modelOverride, multiline: false)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API key")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            SecureField("Paste your key", text: $apiKey)
                                .foregroundStyle(Color.appTextPrimary)
                        }
                        Button(keySaved ? "Saved ✓" : "Save API key") {
                            KeychainStore.save(apiKey, for: KeychainStore.apiKeyAccount)
                            keySaved = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                keySaved = false
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                    }
                    Text("The key is stored securely in the iOS Keychain and only sent to \(provider.displayName) when generating a workout.")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }

                NavigationLink {
                    WikiView(profile: profile)
                } label: {
                    Card {
                        HStack(spacing: 12) {
                            IconWell(systemName: "book.closed")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coach's Notes")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.appTextPrimary)
                                Text("What the coach remembers — readable, editable, rebuildable")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appIconInactive)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Your profile")
                    Card {
                        LabeledField(label: "Name", placeholder: "Name", text: $profile.name, multiline: false)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Primary goal", placeholder: "e.g. rebuild strength", text: $profile.primaryGoal)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Experience")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            PillToggle(selection: $profile.experienceRaw, options: ExperienceLevel.allCases.map {
                                (value: $0.rawValue, label: $0.displayName, icon: nil)
                            })
                        }
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sessions per week")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            CapsuleStepper(value: $profile.daysPerWeek, range: 1...7, step: 1, unit: "days")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Health context")
                    Card {
                        LabeledField(label: "Medical notes", placeholder: "e.g. postpartum, PCOD, thyroid", text: $profile.medicalNotes)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Injuries or limitations", placeholder: "(optional)", text: $profile.injuriesOrLimitations)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Hard limits")
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maximum intensity")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appTextSecondary)
                            PillToggle(selection: $profile.intensityCeilingRaw, options: Intensity.allCases.map {
                                (value: $0.rawValue, label: $0.displayName, icon: nil)
                            })
                        }
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "Never program", placeholder: "comma-separated", text: bannedMovementsText)
                    }
                    Text("Enforced by the app on every generated workout and chat edit.")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Equipment")
                    Card {
                        LabeledField(label: "At home", placeholder: "e.g. dumbbells, band, mat", text: $profile.homeEquipment)
                        Rectangle().fill(Color.appBorder).frame(height: 1)
                        LabeledField(label: "At the gym", placeholder: "e.g. full gym", text: $profile.gymEquipment)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Training styles")
                    LazyVGrid(columns: styleColumns, spacing: 8) {
                        ForEach(TrainingStyle.allCases) { style in
                            Button {
                                toggle(style)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: style.symbol).font(.caption)
                                    Text(style.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    profile.allowedStyles.contains(style) ? Color.appAccent : Color.appSurface,
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(Color.appBorder, lineWidth: profile.allowedStyles.contains(style) ? 0 : 1))
                                .foregroundStyle(profile.allowedStyles.contains(style) ? Color.appBackground : Color.appTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("FlowFit generates workout suggestions with AI and is not a substitute for medical or professional advice. Stop any exercise that causes pain and consult your doctor about your training program.")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func toggle(_ style: TrainingStyle) {
        var styles = Set(profile.allowedStyles)
        if styles.contains(style) { styles.remove(style) } else { styles.insert(style) }
        // Never allow zero styles — the coach needs at least one option.
        if styles.isEmpty { styles.insert(.recovery) }
        profile.allowedStyles = TrainingStyle.allCases.filter(styles.contains)
    }
}
