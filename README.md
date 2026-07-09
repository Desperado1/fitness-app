# AdaptFit

A minimalist iOS workout app with an AI coach. No subscriptions, no single-discipline lock-in — one daily workout, adapted to how you actually feel.

## How it works

1. **One-time profile** — goals, experience, equipment, and health context (e.g. postpartum recovery, PCOD, thyroid). Stored on-device with SwiftData.
2. **Daily check-in** — energy, mood, soreness, minutes available, and (optionally) a preferred style for the day.
3. **AI-generated workout** — the app sends the profile + check-in + recent workout feedback to DeepSeek or Qwen and gets back one structured workout: calisthenics, weightlifting, powerlifting, HIIT, running, or a recovery session.
4. **Post-workout feedback** — a 1–5 "how did it feel" rating plus an optional note. That feedback is included in the prompt for the next workout, so the plan adapts session over session.
5. **History** — every workout and its feedback is stored locally, ready to power a dashboard later.

## Safety by design

The system prompt hard-codes conservative rules: respect medical notes (postpartum → no high-impact plyo or heavy spinal loading; PCOD/thyroid → consistent moderate intensity with strength work), back off when energy is low or recent feedback was negative, never program through reported pain, and only use available equipment and enabled styles. The app also shows a "not medical advice" disclaimer. Still — check with a doctor before starting any program.

## Project setup

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so no `.xcodeproj` lives in git.

```bash
brew install xcodegen
xcodegen generate
open AdaptFit.xcodeproj
```

Requirements: Xcode 15+, iOS 17+ target. No third-party Swift dependencies.

## Configuring the AI coach

1. Get an API key from [DeepSeek](https://platform.deepseek.com) or [Alibaba Cloud Model Studio (Qwen)](https://modelstudio.console.alibabacloud.com).
2. In the app: **Settings → AI coach** — pick the provider, paste the key, tap *Save API key*. The key is stored in the iOS Keychain and only sent to the chosen provider.
3. Defaults: `deepseek-chat` for DeepSeek, `qwen-plus` for Qwen. A different model ID can be typed into the model field.

Both providers expose OpenAI-compatible APIs, so a single client (`LLMClient.swift`) covers both — adding another compatible provider is a one-enum-case change.

## Code map

```
AdaptFit/
├── AdaptFitApp.swift            # App entry, SwiftData container
├── Models/
│   ├── UserProfile.swift        # Profile, training styles, experience
│   └── Workout.swift            # Workout, check-in, feedback, LLM JSON contract
├── Services/
│   ├── LLMClient.swift          # OpenAI-compatible chat client (DeepSeek/Qwen)
│   ├── WorkoutGenerator.swift   # Prompt construction + response parsing
│   └── KeychainStore.swift      # API key storage
└── Views/
    ├── RootView.swift           # Onboarding vs. tab navigation
    ├── OnboardingView.swift     # First-run profile setup
    ├── TodayView.swift          # Daily check-in → generate → today's workout
    ├── WorkoutDetailView.swift  # Workout display, complete/skip
    ├── FeedbackSheet.swift      # Post-workout rating + note
    ├── HistoryView.swift        # Past workouts (future dashboard data)
    └── SettingsView.swift       # Provider/key, profile & health editing
```

## Roadmap

- [ ] Dashboard: trends from stored workouts (consistency, felt-ratings, style mix)
- [ ] Multiple profiles / clients
- [ ] Regenerate today's workout ("something different")
- [ ] Cycle-aware planning for PCOD
- [ ] Optional HealthKit export
