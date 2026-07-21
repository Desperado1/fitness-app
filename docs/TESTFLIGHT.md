# Ship FlowFit to your iPhone via TestFlight (no Mac needed)

Now that you have a paid **Apple Developer Program** membership ($99/yr), this is
the good path: builds install **over the air** through Apple's **TestFlight**
app, each build lasts **90 days** (no more 7-day AltStore refreshes), and you can
add your wife's phone with just her email.

Everything runs on GitHub's cloud macOS runners — you never need a Mac. The
`TestFlight` workflow (`.github/workflows/testflight.yml`) uses
[fastlane](https://fastlane.tools) to sign the app and upload it.

You do a **one-time setup** (all in a browser), then every future build is one
click: **Actions → TestFlight → Run workflow**.

---

## How signing works here (30-second version)

Apple requires two things to install on a real phone: a **distribution
certificate** and a **provisioning profile**. fastlane's `match` creates them
once and stores them, encrypted, in a small **private git repo** so every CI run
reuses the *same* certificate (Apple limits how many you can have). You create
that storage repo once; after that it's automatic.

---

## One-time setup

### 1. App Store Connect API key  (gives CI permission to sign + upload)

1. Go to <https://appstoreconnect.apple.com> → **Users and Access** → **Integrations**
   tab → **App Store Connect API** → **Team Keys**.
2. Click **+**, name it e.g. `FlowFit CI`, role **App Manager**, **Generate**.
3. **Download the `.p8` file** — you can only download it once. Also copy:
   - the **Key ID** (short, next to the key)
   - the **Issuer ID** (at the top of the Keys page)

### 2. Register the app

1. Still in App Store Connect → **My Apps** → **+** → **New App**.
2. Platform **iOS**, pick a name (e.g. `FlowFit`), primary language, Bundle ID
   **`com.flowfit.app`**, and any SKU (e.g. `flowfit`).
   - If `com.flowfit.app` isn't in the Bundle ID dropdown, first register it at
     <https://developer.apple.com/account/resources/identifiers/list> →
     **+** → **App IDs** → **App** → description `FlowFit`, Bundle ID (explicit)
     `com.flowfit.app` → Continue → Register. Then come back and create the app.

### 3. Private repo to store the signing certificate

1. Create a new **private** GitHub repo, e.g. `flowfit-certs` (empty is fine).
2. Create a Personal Access Token that can read/write it:
   <https://github.com/settings/tokens> → **Fine-grained token** → give it
   access to **only** `flowfit-certs`, permission **Contents: Read and write**.
   Copy the token.
3. Make the base64 auth string match needs. In any terminal (or an online base64
   tool), base64-encode `YOUR_GITHUB_USERNAME:YOUR_PAT` — for example:
   ```bash
   printf 'desperado1:github_pat_xxx' | base64
   ```
   Save that output; it becomes `MATCH_GIT_BASIC_AUTHORIZATION`.
4. Pick any passphrase you'll remember — it encrypts the stored certificate.
   Save it as `MATCH_PASSWORD`.

### 4. Add the GitHub secrets

In **this** repo: **Settings → Secrets and variables → Actions → New repository
secret**. Add all six:

| Secret name | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID from step 1 |
| `ASC_ISSUER_ID` | the Issuer ID from step 1 |
| `ASC_KEY_CONTENT` | **base64 of the `.p8` file** — `base64 -i AuthKey_XXX.p8` (macOS/Linux) or `certutil -encode AuthKey_XXX.p8 out.txt` on Windows, then paste the body |
| `MATCH_GIT_URL` | HTTPS URL of your certs repo, e.g. `https://github.com/desperado1/flowfit-certs.git` |
| `MATCH_PASSWORD` | the passphrase from step 3.4 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | the base64 `user:PAT` string from step 3.3 |

> `ASC_KEY_CONTENT` must be the **base64-encoded** contents of the `.p8`, not the
> raw text — the Fastfile decodes it (`is_key_content_base64: true`).

---

## Ship a build

1. GitHub → **Actions** → **TestFlight** → **Run workflow** (~10–15 min).
   - The **first** run creates the certificate + profile and saves them into your
     `flowfit-certs` repo. Every run after that just reuses them.
2. When it finishes, the build appears in App Store Connect → your app →
   **TestFlight** tab. It processes for a few minutes ("Processing").

## Install on your phone

1. Install the **TestFlight** app from the App Store on your iPhone.
2. In App Store Connect → your app → **TestFlight** → **Internal Testing** →
   create a group, add yourself (and your wife) by Apple ID email.
3. You'll get an email / the build shows in TestFlight → **Install**. Updating
   later is just tapping **Update** in TestFlight.

Internal testers (up to 100, must be on your team) install immediately with **no
Apple review**. That's all you need for you + your wife.

---

## Everyday use

- **New build to the phone:** Actions → TestFlight → Run workflow. Build number is
  set automatically from the run number, so it's always accepted.
- **Bump the version** (e.g. `0.1.0` → `0.2.0`) in `project.yml` under
  `MARKETING_VERSION` when you want a new version string.
- **API key on the phone:** the real build (unlike the mock CI tests) needs a
  provider key — set it in **Settings → AI coach** on first launch
  (DeepSeek/Qwen), same as before.

## Troubleshooting

- **`Authentication credentials … invalid` / match can't clone:** re-check
  `MATCH_GIT_URL` (must end in `.git`) and `MATCH_GIT_BASIC_AUTHORIZATION`
  (base64 of `username:PAT`, PAT has Contents write on the certs repo).
- **`No profiles for 'com.flowfit.app'` / signing errors:** make sure the Bundle
  ID is registered (step 2) and the API key role is **App Manager** or Admin.
- **Upload rejected — duplicate build number:** shouldn't happen (run number is
  monotonic), but if you re-run an old run, just start a fresh run.
- **`ITSAppUsesNonExemptEncryption`:** already set to `false` in `project.yml`, so
  no export-compliance prompt.
