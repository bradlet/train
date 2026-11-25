# ADR 2: Rebrand to Train, free forever

## Status

Accepted — 2026-11-25 (issue #11, Phase 1)

## Context

"Hybrid AIthletics" grew out of an AI running coach. The app is now an opinionated **hybrid** training app: aerobic and strength training as peers, built on the belief that consistent hybrid training keeps athletes healthier for longer (see the Product Vision in `CLAUDE.md`). The old name led with AI, was hard to say, and didn't mention strength.

Bundle IDs can't be renamed, so the rebrand means a new bundle ID and a new App Store Connect record. Data doesn't migrate, which is acceptable: the developer is the sole tester and wipes data rather than migrating it. CloudKit has never been enabled, so nothing in iCloud has to move either.

## Decision

### Names

| | Value |
|---|---|
| Home-screen name (`CFBundleDisplayName`) | **Train** |
| App Store name | **Train: Built to Endure** (22 characters) |
| App Store subtitle | **Cardio + strength, all in one** (29 characters) |

- **Why *Built to Endure*:** *Built* suggests strength and *Endure* covers both endurance and longevity, so neither discipline feels secondary. *Train: Hybrid Athlete* and *Train: Run + Lift* were shortlisted but rejected: in a 2026-11-25 App Store search, five or more apps already used "Hybrid Athlete" and the run-and-lift wording was generic. The same searches found no fitness app called "Built to Endure". A web search found no "Built to Endure" trademark, only other "Built…" marks (*BUILT FITNESS*, *BUILT TO MOVE*). **Still to do before Phase 4:** a USPTO search for `BUILT TO ENDURE` in classes 9, 41 and 42.
- **Why this subtitle:** it's a tool suite, not just a planner, so the subtitle has no verbs. It gives cardio and strength equal billing and repeats no word from the name, because Apple ignores repeated words for search. *Cardio* is used rather than *endurance* because it's what people search for, and it doesn't echo *Endure*.
- **Search:** plain "Train" returns only train games and rail travel apps, so discovery depends on the subtitle and the keyword field (see [APP_STORE.md](../APP_STORE.md)).
- **Siri:** phrases use the home-screen name, so "Tell my Train". The existing alternative names (*AI Coach*, *Coach*) carry the natural phrasing; add *Train Coach*.

### Identifiers

| What | Value |
|---|---|
| Bundle ID | `com.bradlet.train` (fixed by the #27 Google OAuth client) |
| Widget | `com.bradlet.train.CoachVoiceWidget` |
| Test targets | `com.bradlet.train.Tests`, `com.bradlet.train.UITests` |
| CloudKit container (the first ever) | `iCloud.com.bradlet.train` |
| Deep-link scheme | `com.bradlet.train://`, in reverse-DNS form so it can't collide with another app's `train://`. The widget URL is `com.bradlet.train://coach/voice`. |
| Exported UTTypes | `com.bradlet.train.exercise`, `com.bradlet.train.strengthexercise` |
| Targets and module | `Train`, `TrainTests`, `TrainUITests`. The widget target stays `CoachVoiceWidget`. |
| Google Sign-In | Client `81188376099-3srh0cv25oblvnoukf7n6tvfqemosggn` in `train-ha-prod` (#27, `docs/CONNECTIONS.md`) |

### Visual identity

- **Icon:** the generated shoe above a tilted dumbbell (`scripts/generate_app_icon.py`). It's already the app icon and the Google consent-screen logo.
- **Accent colour:** `#0077B6` in light mode (4.9:1 contrast on white) and `#00D9FF` in dark mode (10:1 on the iOS dark background). Both come from the icon's cyan, and both pass the 4.5:1 text-contrast minimum. The icon's own neon on white (1.7:1) doesn't. It ships as the `AccentColor` asset in Phase 2, which also clears today's missing-AccentColor build warning.
- **Wordmark:** decided in Phase 4, alongside the App Store screenshots.

### Business model: free forever

- **Every feature is free, permanently.** Paying is optional and does only two things: **support the creator**, or **remove ads**. No feature is ever behind a paywall.
- **Ads, if they come, are contextual (non-personalized) by default**, so "no tracking" stays true. Before any ad ships:
  - update the privacy policy and terms at `bradlet.com/train/`
  - update the App Store privacy labels
  - add App Tracking Transparency only if personalized ads are ever chosen deliberately
- **Messaging:** Apple's Guideline 2.3.7 keeps pricing words out of the name and subtitle. The "free forever" promise goes in the description, the promotional text, the screenshots and `bradlet.com/train/`.
- **This supersedes ADR 1's one-time-payment context.** The on-device coach's rationale gets *stronger*: a free app can't fund per-token server inference either.

### Positioning: your data, from any source

Train is a **hub for your training data**, not a silo:
- bring workouts in from wherever they're recorded (Apple Watch, plus apps such as Strava and Garmin Connect via Apple Health)
- keep everything on your device
- take it out again at any time, as CSV or a live Google Sheet

Listing copy may only claim what has shipped. Direct Garmin import (#22) and the connections dashboard (#21, #23) are described as "coming" until they ship. Other companies' trademarks go in the description only, never in the keyword field (Guideline 2.3.7).

## Consequences

- Phase 2 renames everything in the identifiers table, adds the `AccentColor` asset, and swaps `Info.plist` to the #27 Google client.
- Phase 4 creates the App Store Connect record. Do it as early as possible, because creating the record reserves the name. Phase 4 also designs the wordmark and finalizes [APP_STORE.md](../APP_STORE.md).
- Any monetization work must keep the free-forever promise and update the privacy policy before it ships.
