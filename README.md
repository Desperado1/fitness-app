# FlowFit

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
- **Honest framing**: FlowFit is not medical advice; it assumes doctor clearance for exercise.

## Project setup

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen); no `.xcodeproj` lives in git.

```bash
brew install xcodegen
xcodegen generate
open FlowFit.xcodeproj
```

Requirements: Xcode 15+, iOS 17+ target. No third-party Swift dependencies. Run unit tests with ⌘U (`FlowFitTests`: prompt builders, JSON contracts, validator, wiki budgets).

## Testing without a Mac

Every push runs `.github/workflows/ios.yml` on a free GitHub Actions macOS runner: it generates the project, compiles the app, runs the unit tests, then boots an iPhone 16 simulator and drives the whole app with `FlowFitUITests` — onboarding, planning a week, generating and adjusting a workout, chatting with the coach, feedback, history, and Coach's Notes — attaching a screenshot at every screen. Download the **app-screenshots** artifact from the workflow run to see the app running without owning a Mac.

The UI tests launch the app with `-mock-llm` (canned coach responses from `MockLLMClient.swift` — no API key or credits needed; also handy as an offline demo mode) and `-ui-testing` (throwaway in-memory database).

Note: macOS runners consume GitHub's free minutes at a 10× multiplier on private repos (~200 macOS-minutes/month on the free tier; one run takes ~15). Making the repo public removes the cap.

## Install on your iPhone (AltStore, no Mac needed)

The **Build IPA** workflow produces an unsigned `FlowFit.ipa`; [AltStore](https://altstore.io) signs and installs it with a free Apple ID from a Windows PC. iPhone must be on iOS 17+.

**One-time PC + iPhone setup**

1. On Windows, install **iTunes** and **iCloud** from Apple's website (not the Microsoft Store versions — AltServer needs the desktop builds).
2. Install **AltServer** from [altstore.io](https://altstore.io) and run it (tray icon).
3. Connect the iPhone by USB, then AltServer tray icon → *Install AltStore* → pick the device, and sign in with an Apple ID (a spare one is fine — it's only used for signing).
4. On the iPhone: Settings → General → **VPN & Device Management** → trust the developer profile. The AltStore app now works.

**Each build you want on the phone**

1. GitHub → Actions → **Build IPA** → *Run workflow* (takes ~5 min).
2. Download the `FlowFit-ipa` artifact from the run page and unzip it to get `FlowFit.ipa`.
3. Get the `.ipa` onto the phone (email/Drive/whatever), open it with the **AltStore** app → Install. (Or, from the PC: AltServer tray icon → *Sideload .ipa*.)
4. First launch: set your DeepSeek/Qwen API key in **Settings → AI coach** — the phone build talks to the real provider.

**Living with free signing**

- Apple expires free-signed apps every **7 days**. AltStore refreshes them automatically when the phone is on the same Wi-Fi as a running AltServer — or open AltStore and tap Refresh before the week is up.
- Free accounts allow max **3** sideloaded apps at a time.
- App data (profile, workout history, coach's notes, the API key in the Keychain) survives refreshes and reinstalls of the same app; it's lost only if you delete the app.
- If the trial sticks, the upgrade path is TestFlight via the Apple Developer Program ($99/yr): no PC, no weekly refresh, easy installs for your wife's phone too.

## Install on your iPhone (TestFlight, paid account, no Mac)

With a paid **Apple Developer Program** membership, the **TestFlight** workflow
(`.github/workflows/testflight.yml`) builds a signed IPA on a cloud macOS runner
and uploads it straight to TestFlight — installs are over-the-air, builds last 90
days (no weekly refresh), and you can add other testers by email. After a one-time
secret setup, shipping a build is one click: **Actions → TestFlight → Run
workflow**. Full setup steps: [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md).

## Configuring the AI coach

1. Get an API key from [DeepSeek](https://platform.deepseek.com) or [Alibaba Cloud Model Studio (Qwen)](https://modelstudio.console.alibabacloud.com).
2. In the app: **Settings → AI coach** — pick the provider, paste the key, tap *Save API key*. The key is stored in the iOS Keychain and only sent to the chosen provider.
3. Defaults: `deepseek-chat` (DeepSeek) / `qwen-plus` (Qwen); any model ID can be typed into the model field. Both providers speak the OpenAI chat API, so one client (`LLMClient.swift`) covers both — another compatible provider is a one-enum-case change.

## Code map

```
FlowFit/
├── FlowFitApp.swift             # App entry, SwiftData container
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
FlowFitTests/                    # Parsers, prompts, validator, wiki budgets
```

## Roadmap

- [ ] Dashboard: trends from the raw layer (consistency, felt-ratings, load progression, style mix)
- [ ] UI polish pass (deliberately deferred)
- [x] "Regenerate today's workout" one-tap alternative
- [ ] Cycle-aware planning for PCOD
- [ ] Multiple profiles / clients
- [ ] Optional HealthKit export
