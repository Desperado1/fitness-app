# Backlog / Known Issues

Issues and improvements noted during testing, to pick up in future tasks.

## Reported 2026-07-21

### 1. Coach lacks guardrails (answers off-topic questions)
- **Observed:** Asked the AI coach a random, unrelated question and it answered it.
- **Expected:** The coach should stay scoped to fitness/workout coaching and
  politely deflect or redirect off-topic or out-of-scope questions.

### 2. Onboarding navigation is a one-way trap
- **Observed:** On first login, a way to open **Settings** was available before
  the first onboarding page (entering all the details) was completed. After
  leaving that page, there was no way to go back to it to finish entering the
  details.
- **Expected:** Either block navigation away from onboarding until required
  details are entered, or allow returning to the first onboarding page to
  complete/edit it. Onboarding should not be able to end up half-finished with
  no way back.

### 3. Settings: persistent "save API keys" prompt + keys shown in plaintext
- **Observed:** In Settings, the prompt to save API keys persists even after the
  keys have been saved. The saved keys are also visible in plaintext.
- **Expected:** Clear/hide the "save" prompt once keys are saved, and mask the
  stored keys (e.g. show only a masked value or a "configured" state) instead of
  displaying them in plaintext.

### 4. Today's workout: no recreate/regenerate, and skip can't be resumed
- **Observed:** After creating a workout for today, on the workout screen there
  is no option to recreate/regenerate the workout. The only action is **Skip**,
  and once skipped there is no way to resume it.
- **Expected:** Provide a way to recreate/regenerate today's workout, and allow
  resuming a workout after it has been skipped (skip should not be a dead end).

### 5. Start a workout from the Week page (and sync to Today)
- **Observed:** Workouts can't be started directly from the Week page.
- **Expected:** Allow starting a workout from the Week page itself, for every
  workout in the week (not just today's). When a workout is started from there,
  that state should reflect on the Today page as well (the two views should stay
  in sync).

### 6. Exercise form analysis via camera (future enhancement)
- **Idea:** Analyze the user's exercise form using the camera.
- **Approach:** Use the Apple camera with on-device body-pose detection (Vision
  framework provides joint positions and can derive limb angles). Capture that
  pose data (joints, angles, etc.) as text, then send it to the LLM for form
  analysis and feedback — rather than uploading raw video.
- **Notes:** Keeps analysis lightweight and privacy-friendly (only derived
  text/coordinates leave the device, not the video). Consider on-device
  processing with periodic snapshots of the pose data during a set.

### 7. Warn the user when DeepSeek credits are running low
- **Problem:** Users supply their own DeepSeek API key, but there's no way for
  them to know when their credits are about to run out — AI features would just
  start failing.
- **Approach (proactive):** Query DeepSeek's balance endpoint
  (`GET https://api.deepseek.com/user/balance`, `Authorization: Bearer <key>`),
  which returns `is_available` and `balance_infos` (total/granted/topped-up
  balance). Show remaining balance in Settings and warn when it falls below a
  threshold or when `is_available` becomes false.
- **Approach (reactive fallback):** Detect the insufficient-balance error
  (HTTP 402) from the chat API and show a clear, actionable message ("DeepSeek
  credits exhausted — top up to keep using AI features") instead of a generic
  failure, so a mid-workout request doesn't fail silently.
- **Notes:** Ideally do both — a balance indicator + low-balance warning, plus
  graceful 402 handling.
