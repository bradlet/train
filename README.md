# Hybrid AIthletics

Hybrid AIletics (pronunciation: `/eɪˈθlɛtɪks/`; "ay-THLET-iks") is an iOS exercise tracking application designed for hybrid athletes with a focus on endurance training. It is a *personal* fitness application, explicitly without social aspects to support the notion that our fitness journies should not be built on comparison but through self-motivation to reach our own health and fitness goals.

The app helps plan weekly training routines, record completed workouts, and track mileage over time. It also provides dynamic exercise program insights and suggestions utilizing onboard AI. We explicitly opt to use small language models which can run entirely on your own mobile device for several key reasons:

1. We believe that you should always have complete ownership of your data. Your health data will never be shared with an AI provider / company through any API; it never leaves your phone (though, we do support ICloud storage, but this is highly secure and not shared with 3rd parties).
2. We want you to feel comfortable getting AI insights on your training as often as possible, without worrying about environmental impact: your usage is not adding to the plethora of data centers using energy and water; it's all on-device with lightweight AI models.
3. We will always maintain a **zero-subscription model**. We are tired of the subscription economy, too, and want to provide a highly-functional tool to aid you in your health and endurance competition journey, that will keep you performing at your peak for years to come.

We don't withhold any features from the free app. Upgrade one time only to support the creators and unlock an ad-free experience. Forever.

## Features

### Home (Tab 1)
- **Today's training** — the day's planned aerobic sessions and strength lane, with quick record and "Log Lift" shortcuts
- **Coach entry** — a card that opens the AI coach conversation, plus a mic button for voice-first entry (see [AI Coach](#ai-coach))

### Aerobic Training (Tab 2)
- **Weekly calendar** with one swimlane per day, ordered from your configured week-start day (Settings)
- **Drag-and-drop** to reschedule exercises between days
- **Mileage header** showing planned vs. completed miles for the current week with progress indicator
- **Record workouts** via the checkmark button on any exercise — pre-fills from the plan, all fields editable
- **Recurring series** — schedule an exercise to repeat on a cadence until an end date, optionally progressing every N occurrences; each occurrence is a real, individually editable session
- **Exercise types**: Run, Long Run, Tempo Run, Interval Run, Easy Run, Recovery Run, Walk, Bike, Swim, Hike, Elliptical, Other

### AI Coach
- **On-device, conversational running coach** powered by Google's Gemma 4 E2B running locally via [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), reached from the Home tab by typing or by voice
- Sees the last four weeks of recorded workouts — including two optional radial-dial ratings, **"How did it feel?" (1–5, Very Weak → Very Strong)** and **"How hard was it?" (RPE 1–10)** — the next two weeks of scheduled exercises, and your weekly strength board
- **Acts through tool calls you approve**: it can propose changes to a planned session, record a workout you describe, program a strength day, or move/remove/offload a strength exercise. Nothing changes until you tap Accept
- **Fully offline** after the model download, no API calls, no subscription — aligned with the one-time-payment business model
- Model weights (~4.3 GB) download from Hugging Face only when you choose to from the coach screen, then stay cached for offline use

See [docs/AI_COACH.md](docs/AI_COACH.md) for the contributor guide.

### Strength Training (Tab 3)
- **Kanban-style weekly board** — one lane per weekday, each with an active Plan section and an Offloaded holding section; drag cards to reorder, move between days, or offload
- **Exercise library** of 100 bundled exercises plus your own custom entries, filterable by muscle group, with optional sets × reps plans
- **Weight records** per exercise, tagged by recording type (max, average, first/last/min set)
- See [docs/STRENGTH_TRAINING.md](docs/STRENGTH_TRAINING.md)

### History (Tab 4)
- **Summary stats**: all-time, year-to-date, and month-to-date mileage
- **Monthly calendar** with colored workout indicators and day-tap detail popovers
- **Paginated workout log** sorted by most recent, with lazy-loading scroll
- **CSV export/import** and **Apple Health import** in the toolbar menu
- **Google Sheets Sync** — opt-in auto export of the entire workout history to a personal Google Sheet on every add/edit/delete (one-way; the sheet is overwritten on every save). See [docs/CONNECTIONS.md](docs/CONNECTIONS.md) for setup.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI |
| Data | SwiftData |
| Sync | CloudKit (automatic via SwiftData) |
| On-device LLM | MLX-Swift + Gemma 4 E2B (4-bit, downloaded on first use) |
| Testing | Swift Testing framework |
| Min iOS | 17.0 |

## Project Layout

```
Hybrid AIthletics/
  Models/           SwiftData @Model classes and enums
  Config/           ModelContainer factory, environment keys (units, week start, aiCoach, coachChat, …), UI test fixtures
  Extensions/       Date arithmetic, distance/duration/pace and weight formatting
  Resources/        Bundled strength exercise library (JSON)
  Services/
    AICoach/          On-device coach: service protocol, MLX implementation, chat store, proposal applier, speech-to-text
    ExercisePlanner/  Recurring series generation and bulk edits
    ExerciseLibrary/  Strength exercise library providers
    GoogleSheetsSync/ Google Sheets export
    HealthKitImport/  Apple Health import
    WorkoutCSV/       CSV import/export
  Views/
    Home/             Today's training, coach entry card, coach chat
    AerobicTraining/  Weekly calendar, exercise cards, add/record sheets
    Strength/         Weekly strength board, exercise library
    History/          Summary stats, monthly calendar, workout list, charts
    Settings/         Preferences (units, week start)
    Shared/           Cross-tab form sections and rating dials
  ContentView.swift   Root TabView
  Hybrid_AIthleticsApp.swift  App entry point (injects services)
Packages/AICoachCore/ Shared coach library: prompt builder, tools, decoder, generation config
Packages/AICoachRuntime/ Coach model runtime (MLX): model preset, download, generation loop
Evals/                AI coach evals against the real model on Metal (see docs/EVALS_GUIDE.md)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for architecture documentation, [docs/AI_COACH.md](docs/AI_COACH.md) for the AI coach contributor guide, [docs/EVALS_GUIDE.md](docs/EVALS_GUIDE.md) for running and extending the coach evals, [docs/DATA_MODEL.md](docs/DATA_MODEL.md) for an in-depth data model reference, [docs/adrs/](docs/adrs/) for architectural decision records, [docs/MOBILE_TESTING.md](docs/MOBILE_TESTING.md) for testing on a physical iPhone, and [docs/RELEASING.md](docs/RELEASING.md) for App Store publishing instructions.

## Building

Open `Hybrid AIthletics.xcodeproj` in Xcode 15+ and build for an iOS 17+ simulator or device.

### AI Coach Model

The AI coach model (~4.3 GB, Gemma 4 E2B 4-bit) is not bundled. It downloads from Hugging Face when the user taps Download on the coach screen (never automatically) and is cached locally for offline access. No developer setup is required — `Packages/AICoachRuntime/Sources/AICoachRuntime/ModelLoading.swift` supplies the Hugging Face downloader, since mlx-swift-lm 3.x no longer bundles one.

> **Note:** The app compiles, runs, and passes all tests without any model present. All unit tests use `StubAICoachService`.

### CloudKit Setup

CloudKit sync is configured but requires a container ID registered in the Apple Developer portal. Update the container identifier in:
1. `Hybrid_AIthletics.entitlements` — `icloud-container-identifiers` array
2. Apple Developer portal — register the iCloud container

## Google Sheets Sync Setup

Setup (the GCP project script, the OAuth console checklist, and the `Info.plist` wiring) lives in [docs/CONNECTIONS.md](docs/CONNECTIONS.md).

## Running Tests

Tests use the Swift Testing framework.

### Unit Tests (macOS — fast, no simulator needed)

Run from Xcode (Cmd+U) or via CLI:

```bash
# Run all unit tests on macOS
xcodebuild test -scheme "Hybrid AIthletics" \
  -only-testing:"Hybrid AIthleticsTests"
```

Unit tests run on macOS and don't require a simulator. They're fast and test all SwiftData models, CSV parsing, date/distance formatting, and logic layer code. Tests use `StubAICoachService` so the model is not needed.

### UI Tests (iOS Simulator)

Run UI tests with:

```bash
# Run all UI tests on iPhone 17 simulator
xcodebuild test -scheme "Hybrid AIthletics" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:"Hybrid AIthleticsUITests"
```

UI tests exercise the full app in the simulator and validate multi-step flows like calendar navigation, workout recording, and deletion.

### AICoachCore Package Tests

Test the shared prompt-building library:

```bash
cd Packages/AICoachCore && swift test
```

## Distance Units

All distances are stored internally in miles. A central `AppConfiguration` model controls display units (miles or kilometers), propagated via a SwiftUI `EnvironmentKey`. To switch to metric, update `AppConfiguration.useMetricUnits` — all views react automatically.

## License

This project is licensed under the [MIT License](LICENSE) with the [Commons Clause](https://commonsclause.com/) condition. You are free to view, fork, modify, and contribute to the source code, but you may not sell the software or any product substantially derived from it. See the [LICENSE](LICENSE) file for full terms.
