# Voice Mode, Phase 3: a coach that talks back

Status: **specified, not started.** Written to be picked up cold in a new
session — everything needed to start coding is here.

Branch: `claude/backlog-prioritization-4kthgx`.

---

## 1. The problem

Phase 2 shipped a working hands-free loop. It is not what was asked for.

The complaint, verbatim: *"What you added is a voice option as in a dictation
but what I want is a voice bot where the coach actually talks to me, something
similar to Siri or Gemini audio or ChatGPT voice mode."*

One thing that is **not** the problem, and should not be "fixed": the loop is
already continuous. `CheckInChatView.runVoiceTurn` re-arms listening after
every reply, with no tap between turns. The mechanism is right. The *feel* is
wrong, for four specific reasons:

| # | Gap | Where |
|---|-----|-------|
| 1 | ~4–7s of dead air per turn | 1.0s silence timer + non-streaming LLM call (`LLMClient.swift:123`, `max_tokens: 4096`, `response_format: json_object`) |
| 2 | No barge-in — you cannot interrupt the coach | Deliberate, documented at `SystemSpeechEngine.swift:8-10` |
| 3 | Orb is a 4-state icon swap, not a living thing | `VoiceOrb.swift` — a circle, an SF Symbol, one pulse |
| 4 | Voice is an option behind a button, not the screen | `TodayView.swift:134` — "Talk it through" below ~180 lines of pickers |

## 2. Decisions already made — do not re-litigate

These were settled in discussion. A session picking this up should treat them
as given.

- **Latency is explicitly deferred.** *"Few seconds delay is something that I
  can fix later. But it has to feel alive even though it's a few seconds
  late."* No SSE streaming, no `"say"`-first JSON, no TTS sentence-chunking in
  this phase. Gap #1 stays; this phase makes the wait *feel* like thought
  instead of lag.
- **No realtime speech-to-speech API.** Qwen-Omni's realtime endpoint is the
  interesting long-term option, but it bypasses the six-role `CoachService`
  architecture, needs function calling for check-in fields, costs far more per
  minute, and works for Qwen users only (DeepSeek has no equivalent). Revisit
  after this phase, not during. See §9.
- **The landing page becomes voice-first, with a toggle back to the form.**
  *"When I say the landing page is like Siri or GPT voice I would like a toggle
  at top to switch to the way we have right now as in selectable option."*
- **Both modes write into one state.** Already the design intent
  (`TodayView.swift:131-133`). Switching modes mid-check-in must preserve
  everything answered so far.

## 3. Scope

**In:** amplitude-reactive orb, spoken thinking-filler, tap-to-interrupt, live
field chips, haptics, no-dead-end turns, the voice landing page, the
Voice/Form toggle, the `IntakeConversation` extraction.

**Out:** LLM streaming, true voice barge-in (see §8), realtime APIs, voice
during the workout, any change to `ChatView`'s existing dictation.

---

## 4. Part A — aliveness

The organising idea: **a slow response is fine if something is visibly and
audibly happening the whole time.** Four mechanisms, in order of impact.

### A1. Amplitude-reactive orb

The single biggest signal. The orb must deform continuously to real audio —
the client's voice while listening, the coach's while speaking.

`SpeechEngine` gains a settable callback (the protocol is already `AnyObject`,
so assigning through `VoiceSession`'s `let engine` is legal):

```swift
protocol SpeechEngine: AnyObject {
    /// Live loudness, 0–1, of whichever side is currently making sound.
    var onLevel: ((Float) -> Void)? { get set }
    // ...existing members unchanged
}
```

**`SystemSpeechEngine` — listening.** RMS inside the existing tap
(`SystemSpeechEngine.swift:65`), mapped through a log curve because raw speech
RMS is tiny:

```swift
// ~-50 dB → 0, 0 dB → 1.
let db = 20 * log10(max(rms, 1e-7))
let level = min(1, max(0, (db + 50) / 50))
```

Emit every 3rd buffer (~14 Hz, plenty for animation) — 43 Hz of main-actor
hops for a decorative signal is waste.

**`SystemSpeechEngine` — speaking.** There is no cheap tap on synthesizer
output. Use `AVSpeechSynthesizerDelegate.willSpeakRangeOfSpeechString` on the
existing `SpeechCompletionDelegate` and emit a per-word bump
(`Float.random(in: 0.45...0.9)`). Smoothed, this reads as a natural speech
envelope. **Comment it honestly** — it is word-boundary driven, not true
output amplitude.

**`VoiceSession`** exposes `@Published private(set) var level: Double = 0`,
smoothed with an EMA (`level = level * 0.6 + new * 0.4`) so the orb glides
rather than strobes, and reset to 0 in `stop()` / `stopListening()`.

**`VoiceOrb.swift`** is reworked into one parameterised orb taking `phase`,
`level` and a size, used at ~64pt in the sheet and full-bleed on the landing
page. Use `TimelineView(.animation)` with ~3 offset, blurred, slowly-rotating
circles scaled by `level` — organic motion with no animation state to manage.
Keep it to 3 shapes and moderate blur; `TimelineView` plus heavy blur is a
real cost.

### A2. Spoken thinking-filler — the key trick

The instant an utterance is submitted, the coach says something short *while
the network call is in flight*. This is what humans do, and it converts 4
seconds of dead air into 4 seconds of someone thinking.

New `FlowFit/Services/ThinkingFiller.swift`:

```swift
struct ThinkingFiller {
    static let phrases = [
        "Got it.", "Right.", "Mm-hm.", "Okay.",
        "Gotcha.", "Sure.", "Okay, one sec.", "Right, let me think.",
    ]
    private var lastIndex: Int?
    mutating func next() -> String { /* random, never the same twice running */ }
}
```

Keep phrases short and non-committal. Anything longer collides with the real
reply; anything that pretends to have understood ("that sounds rough") is a
guess, because the model has not answered yet. Never repeat consecutively — a
repeat is the clearest tell that it is canned.

**Sequencing matters.** Start the LLM `Task` *first*, then speak the filler,
then await the result — otherwise the two serialise and the filler adds
latency instead of hiding it:

```swift
let pending = Task { await conversation.send(utterance) }
await voice.fillThinkingPause()   // ~0.8s, overlaps the call
let reply = await pending.value
```

`fillThinkingPause()` must hold `phase == .thinking`, not `.speaking` — the
loop genuinely is thinking and the orb should not claim otherwise. This needs
a private `rawSpeak` in `VoiceSession`, since `speak(_:)` sets `.speaking` and
resets to `.idle`.

### A3. Tap-to-interrupt

True voice barge-in is out of scope (§8). But being trapped in a monologue is
exactly the dictation feeling, and tapping is a cheap, fully-testable escape.

Tapping the orb while `.speaking` stops the synthesizer and proceeds straight
to listening. This falls out almost free: `SpeechCompletionDelegate.finish()`
already fires on `didCancel` (`SystemSpeechEngine.swift:192`), so the
continuation inside `speak(_:)` resumes and `runVoiceTurn` walks on to
`listen` by itself. `VoiceSession.interruptSpeaking()` is just
`engine.stopSpeaking()`.

Note this **changes existing behaviour**: today, tapping the orb calls
`voice.stop()` and kills voice mode entirely (`CheckInChatView.swift:208-212`).
Leaving voice mode needs its own separate control on the new screen.

### A4. Never dead-end

`VoiceSession.submit()` currently drops to `.idle` and discards the handler on
an empty utterance (`VoiceSession.swift:196-199`) — silently, which looks like
the app died. Re-arm listening with the same handler instead, and surface a
"didn't catch that" hint.

### A5. Haptics

`.sensoryFeedback(.success, trigger:)` when a turn is captured and when a
field lands. Physical response reads as alive and costs one modifier.

---

## 5. Part B — the voice-first landing page

### B1. Where it goes

`TodayView` already branches (`TodayView.swift:41`): workout exists →
`WorkoutDetailView`; no workout → the check-in form. **The no-workout branch
becomes the voice screen.** That is exactly the moment there is nothing to
display anyway, and it leaves `WorkoutDetailView` untouched.

### B2. The toggle

Top of the screen, persisted in `@AppStorage("checkInMode")` so the choice
sticks across launches. Two modes:

- **Voice** (new default) → `VoiceCheckInView`
- **Form** → the existing `checkInScreen`, unchanged

A small segmented control or two icons (`waveform` / `slider.horizontal.3`).
It must be visible without scrolling in both modes.

### B3. `VoiceCheckInView`

Full-bleed, dark, orb-centred. Contents, top to bottom:

1. the mode toggle
2. the orb, large, filling most of the screen
3. one line of live transcript — `voice.partialTranscript` while listening,
   the coach's last line otherwise
4. **the field chips** — reuse `CheckInChatView`'s `knownStrip`
5. a small "End" / exit control

**Do not auto-start the mic on appear.** Neither reference app does — ChatGPT
requires a tap to enter voice mode. Show the orb idle with "Tap to start",
then run fully hands-free for the rest of the session. Auto-hot-mic on every
app launch is a real privacy and battery cost for no gain.

**The chips are not decoration.** A bare orb with no feedback is unnerving —
you cannot tell whether it heard "no shoulder pain" or "shoulder pain".
Watching fields populate is the trust mechanism, and `knownFields` already
exists, so it is nearly free.

### B4. Mode split

With voice on the landing page, voice inside the chat sheet is redundant.
Clean split:

- **Voice mode** = the orb landing page (all voice lives here)
- **Form mode** = pickers + the typed chat sheet

So **remove voice from `CheckInChatView`** — the mic button in the composer
(`CheckInChatView.swift:284-294`), `voiceControls`, `startVoiceMode`,
`runVoiceTurn`. It keeps the typed conversation only. This deletes code rather
than adding it; `VoiceSessionTests` cover `VoiceSession`, not the view, so
they are unaffected. `ChatView`'s dictation is separate and stays.

### B5. `IntakeConversation` — shared state

Both surfaces need the same conversation logic. Do **not** duplicate `send()`
(`CheckInChatView.swift:325-365`) — it holds field application, the
ready-latch, and error recovery, and a drift between the two paths would be a
real bug.

Extract `FlowFit/Services/IntakeConversation.swift`:

```swift
@MainActor
final class IntakeConversation: ObservableObject {
    @Published var checkIn = DailyCheckIn()
    @Published var knownFields: Set<CheckInField> = []
    @Published private(set) var transcript: [IntakeTurn] = []
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    private var coachSaysReady = false

    var isReady: Bool {
        coachSaysReady || CheckInField.required.allSatisfy { knownFields.contains($0) }
    }

    func configure(profile: UserProfile, session: PlannedSession?, wikiContext: String)
    func send(_ text: String) async -> String?
}
```

`TodayView` owns it as `@StateObject`, replacing its three `@State`
properties (`checkIn`, `knownFields`, `intakeTranscript`) and passing it to
both views. The form binds to `$conversation.checkIn.energy` and so on —
binding through to a nested property of a `@Published` struct works fine.

This is the one genuine refactor in the phase. It is worth it: it is what
makes "talking and tapping are two ways into one state" true across screens
rather than just within the sheet.

---

## 6. Files

**New**
- `FlowFit/Services/ThinkingFiller.swift`
- `FlowFit/Services/IntakeConversation.swift`
- `FlowFit/Views/VoiceCheckInView.swift`

**Modified**
- `FlowFit/Services/VoiceSession.swift` — `level`, `fillThinkingPause`, `interruptSpeaking`, empty-utterance re-arm
- `FlowFit/Services/SystemSpeechEngine.swift` — `onLevel`: RMS in, word-boundary out
- `FlowFit/Services/ScriptedSpeechEngine.swift` — synthetic levels so CI drives the orb
- `FlowFit/Support/VoiceOrb.swift` — parameterised, amplitude-reactive
- `FlowFit/Views/TodayView.swift` — toggle, `IntakeConversation`, view swap
- `FlowFit/Views/CheckInChatView.swift` — use the conversation object, drop voice
- `FlowFitTests/VoiceSessionTests.swift` — extend
- `README.md` — roadmap and feature description

`project.yml` needs **no change**: `sources: [FlowFit]` is a directory glob,
so new files are picked up by `xcodegen generate` automatically.

## 7. Tests

The existing 10 `VoiceSessionTests` must keep passing — they encode
turn-detection policy and none of it is changing. `TestSpeechEngine` there
needs an `onLevel` property to satisfy the protocol.

Add:

- `ThinkingFiller` never returns the same phrase twice consecutively (call it
  ~20 times), and every phrase is in the pool
- `VoiceSession.level` tracks engine levels and smooths (a step input does not
  jump straight to the target)
- `level` returns to 0 on `stop()`
- an empty utterance re-arms listening instead of going idle (A4)
- `interruptSpeaking()` stops speech and resolves the `speak` continuation
- `IntakeConversation.send` applies a patch to `knownFields`, latches
  `isReady`, and restores the transcript on error

Run via the `.github/trigger-ci` push path — touch that file to fire
`ios.yml`. `-mock-voice` + `-mock-llm` should still walk a whole hands-free
check-in and screenshot the orb.

## 8. Risks

- **`ScriptedSpeechEngine` must emit levels**, or CI screenshots show a dead
  orb and the headline feature is invisible to the Mac-less workflow.
- **`TimelineView(.animation)` + blur** is the one performance risk. Profile
  on device; drop to fewer layers if it costs frames.
- **True voice barge-in stays out of scope.** It needs `AVAudioSession`
  `.voiceChat` mode for hardware echo cancellation, and cannot be validated
  from here or in CI — the simulator has no usable microphone. A3's
  tap-to-interrupt is the testable substitute. Revisit on device.
- **`SFSpeechRecognizer` tasks have a ~1 minute ceiling.** Invisible today
  because turns are short; a longer continuous session will need task
  recycling. Not addressed in this phase — note it if it surfaces.

## 9. Deferred

In rough priority order once this lands:

1. **Latency** — SSE streaming from `LLMClient`, the spoken line first in the
   JSON as a `"say"` key so it can be stream-parsed, sentence-chunked TTS.
   Realistically ~1.5s to first audio, capped by DeepSeek/Qwen TTFT.
2. **True voice barge-in** — `.voiceChat` AEC, mic open during playback.
3. **Realtime speech-to-speech** — Qwen-Omni over WebSocket, behind a Settings
   toggle, as an opt-in for Qwen users. Needs function calling to write
   check-in fields and wiki context in the session instructions. Verify the
   current endpoint and model names before committing to this.
4. **Voice during the workout** — already on the README roadmap: "next
   exercise", "I did 8 not 10" mid-set.

## 10. Done when

- The landing page is the orb, with a working Voice/Form toggle that persists
  and preserves answers across a mid-check-in switch.
- The orb visibly tracks the client's voice while listening and the coach's
  while speaking.
- No silence longer than ~1s passes without something happening — the filler
  covers the model round trip.
- The coach can be cut off mid-sentence with a tap.
- Fields visibly land as chips as they are understood.
- A complete check-in can be done without touching the screen after the first
  tap, and the workout generates at the end.
- `ios.yml` is green.
