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
