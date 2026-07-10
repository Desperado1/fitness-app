# AdaptFit

A minimalist iOS workout app with an AI coach. No subscriptions, no single-discipline lock-in — a weekly plan that adapts every day to how you actually feel.

## How it works

1. **One-time profile** — goals, experience, home + gym equipment, health context (e.g. postpartum recovery, PCOD, thyroid), and hard limits. Stored on-device with SwiftData.
2. **Plan my week** — the coach designs a weekly training block (sessions with focus, style, exercises, target weights) that carries progression from week to week.
3. **Daily check-in** — energy, mood, soreness, home or gym, minutes available. The coach *modulates* today's planned session to fit: low energy shrinks it, no gym swaps the equipment, a rough week turns it into recovery. Structure holds the skeleton; mood turns the dial.
4. **Do it, log only what changed** — every exercise defaults to "done as prescribed"; tap to adjust actual sets/reps/weight or skip. Talk back anytime: a per-workout chat where the coach explains choices and applies edits ("my wrists hurt, swap the push-ups").
5. **Feedback** — a 1–5 "how did it feel" rating plus a note. This, with your actuals, drives the next session and the next week.

## Architecture: three layers + one coach, five roles

Inspired by [Karpathy's LLM-wiki idea](https://aaif.io/blog/karpathys-llm-wiki-as-agent-memory/): the model maintains a lean, human-readable knowledge base instead of re-reading raw data.

1. **Raw layer (ground truth, LLM read-only)** — SwiftData: profile, training blocks, workouts with prescriptions *and* actuals, feedback, chat transcripts. Never touched by the LLM. This is also the future dashboard's data source.
2. **Wiki layer (the coach's memory, LLM-owned)** — five size-budgeted markdown pages: `profile`, `progressions` (current working numbers, copied verbatim from raw data), `observations` (patterns over time), `current-block`, `log`. Visible and editable in-app as **Coach's Notes**, snapshotted on every change, and rebuildable from raw history at any time.
3. **Schema layer** — `WikiSchema.swift`: page purposes, budgets, and conventions included in every wiki-writing prompt.

Every LLM call goes through `CoachService`, one of five roles sharing the same memory:

| Role | Reads | Writes |
|---|---|---|
| Planner | wiki + profile + last block | next week's `TrainingBlock` |
| Modulator | wiki + planned session + today's check-in | today's concrete workout |
| Chat coach | wiki + today's workout + thread | reply + optional structured workout edit |
| Scribe | wiki + completed workout (actuals, feedback) | updated wiki pages |
| Rebuild | profile + full raw history | the whole wiki, fresh |

## Safety by design

- **Code-level guardrails** (`WorkoutValidator.swift`), independent of prompts: intensity is clamped to the profile's ceiling; banned movements and disabled styles cause a regeneration with the violation fed back, then a visible error — never a silent pass. Unsafe chat edits are refused.
- **Prompt-level rules**: postpartum → no high-impact plyo, no heavy spinal loading, pelvic-floor-friendly core work; PCOD/thyroid → consistent moderate intensity with strength emphasis; low energy or negative feedback → deload; never program through reported pain.
- **Honest framing**: AdaptFit is not medical advice; it assumes doctor clearance for exercise.

## Project setup

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen); no `.xcodeproj` lives in git.

```bash
brew install xcodegen
xcodegen generate
open AdaptFit.xcodeproj
```

Requirements: Xcode 15+, iOS 17+ target. No third-party Swift dependencies. Run unit tests with ⌘U (`AdaptFitTests`: prompt builders, JSON contracts, validator, wiki budgets).

## Configuring the AI coach

1. Get an API key from [DeepSeek](https://platform.deepseek.com) or [Alibaba Cloud Model Studio (Qwen)](https://modelstudio.console.alibabacloud.com).
2. In the app: **Settings → AI coach** — pick the provider, paste the key, tap *Save API key*. The key is stored in the iOS Keychain and only sent to the chosen provider.
3. Defaults: `deepseek-chat` (DeepSeek) / `qwen-plus` (Qwen); any model ID can be typed into the model field. Both providers speak the OpenAI chat API, so one client (`LLMClient.swift`) covers both — another compatible provider is a one-enum-case change.

## Code map

```
AdaptFit/
├── AdaptFitApp.swift             # App entry, SwiftData container
├── Models/                       # Raw layer (ground truth)
│   ├── UserProfile.swift         # Profile, styles, equipment, hard limits
│   ├── TrainingBlock.swift       # Weekly plan + LLM block contract
│   ├── Workout.swift             # Prescription + actuals, check-in, LLM workout contract
│   ├── WikiPage.swift            # Wiki layer storage w/ snapshots
│   └── CoachChatMessage.swift    # Chat transcripts
├── Services/
│   ├── LLMClient.swift           # OpenAI-compatible chat client (DeepSeek/Qwen)
│   ├── CoachService.swift        # Five roles: prompts + parsing
│   ├── WikiSchema.swift          # Schema layer: pages, budgets, conventions
│   ├── WikiStore.swift           # Wiki seeding, context, updates, rollback
│   └── WorkoutValidator.swift    # Code-level safety guardrails
└── Views/
    ├── RootView.swift            # Onboarding vs. tabs
    ├── OnboardingView.swift      # First-run profile setup
    ├── PlanView.swift            # Weekly block + "Plan my week"
    ├── TodayView.swift           # Check-in → modulated workout
    ├── WorkoutDetailView.swift   # Per-exercise logging, complete/skip
    ├── ChatView.swift            # Talk back; coach applies edits
    ├── FeedbackSheet.swift       # Rating + note; fires the scribe
    ├── WikiView.swift            # Coach's Notes: edit, restore, rebuild
    ├── HistoryView.swift         # Past workouts
    └── SettingsView.swift        # Provider/key, profile, hard limits
AdaptFitTests/                    # Parsers, prompts, validator, wiki budgets
```

## Roadmap

- [ ] Dashboard: trends from the raw layer (consistency, felt-ratings, load progression, style mix)
- [ ] UI polish pass (deliberately deferred)
- [ ] "Regenerate today's workout" one-tap alternative
- [ ] Cycle-aware planning for PCOD
- [ ] Multiple profiles / clients
- [ ] Optional HealthKit export
