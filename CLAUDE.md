# CLAUDE.md

## Project
Train (App Store: *Train: Built to Endure*; see `docs/adrs/2-rebrand-to-train.md`) — iOS hybrid training app (SwiftUI + SwiftData + CloudKit sync). Free forever: never paywall a feature.

## Product Vision
An **opinionated** training app for planning, scheduling, and tracking athletic training. Its core belief, which every feature should promote: **consistent hybrid training — aerobic *and* strength — keeps athletes of every level healthier, less injury-prone, and performing better much later in life.** Aerobic training came first, but strength is a first-class peer, not an add-on tab.
- **Hybrid by default.** When a feature touches one discipline, consider the other: shared surfaces (Home, History, stats, the coach, sync/export) should represent both, and nothing should make strength feel second-class.
- **Opinionated, low-friction UX.** Planning and recording must be fast. Prefer a well-chosen default over a configuration screen, and stay high-level where precision adds friction (e.g. strength records one weight per session with a chosen measurement — max, average, … — never per-rep/per-set logs).
- **The athlete decides what is hard.** Key (hard) workouts are whatever the athlete marks as key, via a per-session flag plus their own per-type defaults. Never infer intensity from exercise type, distance, pace, or RPE, and make every hard-workout analysis (placement, hints, stats) respect that marking.
- **Strength and cardio quick actions stay visibly distinct.** One-tap strength logging is strength-only and labelled as such; it never sits where it could be mistaken for completing the day's runs.
- **Target structure: two parallel flows.** Home (Today first, hybrid hub below) · **Cardio** (Plan | Progress) · **Strength** (Plan | Progress). New surfaces fit that pattern rather than adding discipline-specific tabs.
- Feature plans for this direction live in `docs/planning/` (start at its README).

## Build & Test
```bash
# Build app
xcodebuild -scheme Train -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run app unit tests
xcodebuild test -scheme Train -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"TrainTests"

# Run History tab functional UI tests
xcodebuild test -scheme Train -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"TrainUITests/HistoryUITests"

# Run AICoachCore / AICoachRuntime package tests (no model)
cd Packages/AICoachCore && swift test
cd Packages/AICoachRuntime && swift test

# AI coach evals — production model on the Mac's GPU (first run: release build + ~4.3 GB download)
cd Evals && ./coach-eval run --samples 3            # all scenarios, graded
cd Evals && ./coach-eval run --save --note "…"      # save to Evals/results/, then ./coach-eval compare
cd Evals && ./coach-eval inspect --scenario record-yesterday   # exact prompt + tool schemas, no model
cd Evals && ./coach-eval chat                       # interactive REPL against the real model
cd Evals && swift test                              # CoachEvalKit unit tests, no model

# App icon — regenerate after editing the script (needs only uv; Pillow comes via inline metadata)
uv run scripts/generate_app_icon.py                          # overwrites the AppIcon asset
uv run scripts/generate_app_icon.py --output /tmp/icon.png   # preview without touching the asset
```

## App Icon
The app icon is **generated, never hand-edited**: `scripts/generate_app_icon.py` draws it and writes `Train/Assets.xcassets/AppIcon.appiconset/app-icon.png` (1024×1024, opaque — iOS rejects alpha; `Contents.json` stays untouched). To change the icon/logo, edit the script and re-run it, then commit the script and the PNG together. Every design knob is a named constant at the top of the script:
- **Shape**: `START`/`OUTLINE` (the shoe's side profile as cubic Béziers, toe right, y down), `MIDSOLE_CUT` and `SPEED_SLASHES` (tapered white negative-space cuts).
- **Placement**: `SHOE_WIDTH` (fraction of the canvas) and `CENTER` — the shoe (with the dumbbell beneath it) sits small in the top-right corner like the heart in Apple's Health icon; keep it clear of iOS's rounded-corner mask.
- **Colour**: `NAVY_TOP`→`NAVY` (upper's subtle gradient), `NEON_STOPS` (glossy midsole gradient), `HIGHLIGHT*` (specular streak on the midsole), `SPLIT_CURVE`/`NEON_SIDE` (where navy meets neon — today the midsole line).
- **Dumbbell** (the strength half of the mark): `DUMBBELL_SPAN` (width as a multiple of the shoe's), `DUMBBELL_TILT` and `DUMBBELL_SHIFT` (together they nest the toe in the angle between handle and right plate), `DUMBBELL_GAP` (white space kept from the shoe in *every* direction — the dumbbell is raised until it would cross it), the part sizes `HANDLE_*`/`COLLAR`/`WEIGHTS`, and `WEIGHT_STOPS` (one gradient per plate, inner → outer: navy inner, neon outer).
- **Shadow**: `SHADOW_*` (soft drop shadow, cast from the solid shoe and dumbbell outlines so the white cuts stay white).

Check a change by previewing with `--output` at full size *and* downscaled to ~60 px (home-screen size) before overwriting the asset.

## Architecture
The AI coach has a full contributor guide in `docs/AI_COACH.md`, and its evals have `docs/EVALS_GUIDE.md` — keep both in step with the coach notes below.

- **No ViewModels** — `@Query` in top-level views only (`HomeView`, `AerobicTrainingView`, `StrengthTrainingView`, `HistoryView`, `SettingsView`, `ContentView`). Child views receive data as `let` parameters. App-scope observable state that isn't a ViewModel (owns no queries, makes no view decisions) is a `@MainActor @Observable` service injected via `@Environment` — see `GoogleSheetsSyncCoordinator` and `CoachChatStore`.
- **Models**: `Exercise` (a planned and/or recorded activity), `Workout` (its recorded actuals — a Codable value JSON-encoded on the exercise, not a `@Model`), `StrengthExercise` (strength board card, with `StrengthWorkout` lift records encoded the same way), `UserLibraryExercise` (custom library entries), `FavoriteWorkout` (saved aerobic presets), `AppConfiguration` (preferences), `ExerciseType` (enum)
- **Distance storage**: Always miles internally. Display conversion via `Double.formattedDistance(metric:)`. Unit preference via `@Environment(\.useMetricUnits)`.
- **Week start**: Monthly calendar grids are always Sunday-first — standard `Calendar.current` week (see `Date+Week.swift`). The user's `AppConfiguration.weekStartDay` (1=Sun…7=Sat, injected via `@Environment(\.weekStartDay)`) governs (a) weekly *aggregation* (mileage buckets, "This Week" stats — threaded into `WorkoutAggregations` as `firstWeekday`) and (b) the Aerobic Training *weekly* calendar: its day ordering, week boundaries, navigation, and header mileage totals use the `firstWeekday:` variants (`daysInWeek(firstWeekday:)`, `startOfWeek(firstWeekday:)`, `endOfWeek(firstWeekday:)`) so the topmost swimlane is the configured week start. The no-arg Sunday-first helpers remain for monthly views and must not change.
- **CloudKit is on, with container `iCloud.com.bradlet.train`** (first enabled by the Train rename, #11). `ModelContainerFactory.makeContainer()` syncs via `cloudKitDatabase: .automatic`; `makePreviewContainer()` (previews, unit tests, `-uiTestSeed`) is explicitly `.none` so fixture data never mirrors. CloudKit's **production schema is additive only**: every model property needs a default value (or is optional), no `@Attribute(.unique)`, relationships optional, and never rename or remove a deployed field. Any change to where data goes (sync, export, ads) must update the privacy policy at bradlet.com/train/privacy/ first.
- **Activity opted out of training progress is visually distinct.** `Exercise.countsTowardMileage == false` surfaces as a hollow calendar dot (via `CalendarDisplayable.countsTowardTraining` → `CalendarDayDot`) and a dimmed History row carrying a "Not training" badge. A day mixing counted and opted-out activity still draws a solid dot — it *was* a training day.
- **Feeling and perceived exertion are two independent fields**, never one. `Workout.feeling` is 1–5 (Very Weak → Very Strong) and `Workout.perceivedExertion` is RPE 1–10; both are `Int?` with `nil` meaning "not recorded". The AI coach prompt emits each verbatim and omits it when `nil` — there is no inversion or derivation between them (there used to be, and it was wrong). Charts of feeling must plot `nil` as a **gap**, never as `0`.
- **Enums in @Model classes** must be plain raw-value Codable enums (like `ExerciseType`). An enum with a custom `init(from:)` (e.g. `MuscleGroup`'s tolerant decode) makes SwiftData treat it as a composite Codable attribute and its encoder crashes on save — store the raw String instead and expose a computed enum property (see `StrengthExercise.muscleGroupRaw`, `Workout.source`).
- **AICoachCore local package**: `Packages/AICoachCore/` — shared library containing prompt builder, coaching types (`CoachWorkout`, `CoachExercise`, `CoachStrengthExercise`, `CoachingRequest`, `CoachingResponse`), formatters, and `GenerationConfig`. Used by both the iOS app and the `Evals/` CLI. The app converts SwiftData models to AICoachCore types via `CoachTypeConversions.swift`.
- **AICoachRuntime local package**: `Packages/AICoachRuntime/` — the **only** code that imports MLX. `CoachModelPreset.production` (model id, tool-call format as a raw string, EOS tokens, download size — they change together), `CoachRuntime` (load + `streamChat(_:today:config:)`: turns → generate → tool call → `CoachEvent`), `CoachEventMapping`, and the Hugging Face loading code. `MLXAICoachService` is a thin adapter over it, and `Evals/` generates through the same `CoachRuntime`, so evals measure the code the app ships. `today` is a parameter (the app passes `Date()`, evals pin it).
- **Evals run the real model, in Swift, on Metal.** SwiftPM in the Swift 6.4 toolchain compiles mlx-swift's Metal shaders (`default.metallib` in `.build/…/mlx-swift_Cmlx.bundle`), so `Evals/` needs no Python and no Xcode build. `CoachEvalKit` (scenarios, `Expectation` checks, runner, Codable `RunRecord`) is MLX-free and unit-tested; `TurnTranscript.fold` and `EvalScenario.chatRequest()` deliberately mirror `CoachChatStore`'s first-proposal-wins and snapshot-on-first-request rules — change them together. Keep `Evals/Package.resolved` and `Packages/AICoachRuntime/Package.resolved` pinned to the app's mlx-swift / mlx-swift-lm / swift-transformers / swift-jinja / swift-huggingface revisions — SwiftPM resolves each package independently and *will* drift (swift-jinja renders the chat template); `PinnedVersionsTests` in `cd Evals && swift test` fails when they differ. Guide: `docs/EVALS_GUIDE.md`.
- **AI Coach service layer**: `AICoachService` protocol with two implementations — `MLXAICoachService` (production, Gemma 4 E2B via `CoachRuntime`) and `StubAICoachService` (previews/tests/UI tests). Injected via `@Environment(\.aiCoach)`. Default environment value is the stub so previews never load real models. Uses `UserInput(chat:)` with separate system/user roles for proper chat template formatting. The app root injects the stub under `-uiTestSeed` so UI tests never trigger the model download.
- **The coach is tool-calling.** `streamChat` yields `CoachEvent`s (`.textChunk` / `.action` / `.rejectedToolCall`), mirroring the runtime's `Generation` cases so no app code imports MLX (only `Packages/AICoachRuntime` does). Five tools live in `CoachToolSchemas`: `chat`, `suggest_schedule_change`, `plan_strength_day`, `update_strength_exercise`, `record_workout`. **The mutating tools propose, never write** — a tool call becomes a pending proposal the athlete accepts, applied via `CoachProposalApplier` (schedule changes, strength days, strength-exercise updates) or a pre-filled `RecordWorkoutSheet` (workouts). Decode and validate through `CoachToolDecoder`, **not** the runtime's `ToolCall.execute(with:)`, whose hardcoded `JSONDecoder` can't parse a model-emitted `"2026-04-06"`. Out-of-range ratings are rejected, never clamped.
- **The strength board is in the coaching snapshot and has two tools.** `CoachingRequest.strengthExercises` carries board snapshots (`CoachStrengthExercise` lives in AICoachCore; the SwiftData bridging and board-order `snapshots(from:)` live in `CoachTypeConversions.swift`), rendered as a "Strength board" prompt section of active lanes only. `plan_strength_day` *adds*: a whole weekday lane in ONE call (first-proposal-wins would drop split calls) — it takes a weekday *name*, never a date, because the board is a weekly template — and it appends, never replaces, so a one-item call is also how the coach adds an individual exercise. Its decoder caps the batch at `StrengthDayProposal.maxExercises` (8) and requires sets/reps together within the `StrengthPlanDraft` ranges; its applier inserts at the lane end, matches names against the merged library for provenance, and skips — never duplicates — names already in the lane's active section, reporting skips in the confirmation note. `update_strength_exercise` *changes what is already on the board*: remove, move to another day, offload, or onboard ONE exercise, addressed by weekday + name as listed in the prompt. Both decode with case-insensitive weekday/group matching; the update applier resolves names the same way and fails loudly on no match or a move-collision rather than inventing exercises or duplicating names.
- **The model has no clock — every conversational turn carries today's date.** `chatSystemPreamble(today:)` opens with a calendar anchor (today, yesterday, tomorrow) and `CoachToolSchemas.all(today:)` names today in each date argument's description. It lives in the *system* turn, not the training snapshot, because the snapshot attaches only once per conversation. Don't put a fixed example date in a date description: the `"e.g. 2026-04-06"` that used to sit in the schemas was being emitted verbatim as the workout date, months off from when the athlete trained.
- **A tool call is the last step, not the opening move.** The chat preamble and `record_workout`'s own description both state what has to be known first (date, type, and a distance or duration), name "can you record a workout for me" as the case that supplies none of it, and send the model back to the `chat` tool to ask. `CoachToolDecoder` enforces the size half: a workout proposal with neither distance nor duration is rejected, as a schedule change with no new value already was.
- **`plan_strength_day`'s `exercises` is a flat line-format string, never a nested array of objects.** Verified end-to-end against the production model: the Gemma 4 dialect writes strings with a `<|"|>` escape marker that mlx-swift-lm's `GemmaFunctionParser` only unwraps for *scalar* values — a value starting with `[` falls to `BareKeyJSONParser`, which cannot read the markers, so even a perfect dialect-conformant nested call arrived as one raw string and died at decode ("The coach left out a required value (exercises)") while every flat tool (record_workout, suggest_schedule_change, update_strength_exercise) worked. The string format — `Name (Muscle Group), sets x reps`, semicolon-separated — mirrors the strength-board lines the prompt already shows, and `CoachToolDecoder` parses it deterministically (the array-of-objects path stays as a fallback). The chat preamble also names each tool's required fields verbatim, because a 4B model reads schema `required` arrays weakly.
- **The preamble names every tool's required fields because the schema's `required` array is not enough.** A 4B model reads JSON-schema constraints weakly — `plan_strength_day` arrived once with a weekday and rationale but no `exercises`, the picks written in prose. The chat preamble now states each tool's required fields verbatim ("A tool call's required fields go IN the call, never only in your reply text"), says explicitly that the *coach* chooses the exercises for `plan_strength_day` (programming the day is the ask; the athlete never names the lifts), and the `exercises` field description is marked `REQUIRED`. `CoachToolDecoder` remains the enforcement net underneath.
- **The first proposal of a turn wins.** A small model emits the same call two or three times in one pass, each slightly different; `CoachChatStore` ignores every `.action` proposal after the first so the card can't rewrite itself under the athlete's finger. Streamed text keeps appending either way.
- **The coach model download is always an explicit opt-in.** `CoachModelPhase` distinguishes `.notDownloaded` / `.downloading` / `.downloaded` / `.loadingIntoMemory` / `.ready` / `.failed`. `CoachChatStore.checkAvailability` (Home, on appear) only inspects the filesystem, and `prepareModel` (chat, on appear) only *loads* an already-cached model — neither ever starts a download. Only `downloadModel(coach:)`, called from the chat's call-to-action button, does that. Chat is visibly greyed out (dimmed composer + disabled suggestions) until `.ready`, and the Home card dims and re-labels itself to advertise the download.
- **Download progress is weighted by bytes, not files, and assembled one file at a time.** `HubApi.snapshot`'s top-level `Progress` gives each *file* one unit regardless of size; the model repo is one 4.3 GB weights file beside nine totalling ~33 MB, so that fraction hits 90% in seconds and then crawls. Watching the filesystem instead does **not** work either, though it looks like it should: the transfer runs through `URLSession.download`, which streams into the *system temp directory* and only `moveItem`s into the repo directory once a file is complete — so a repo poll shows nothing for minutes, then 4.3 GB at once (this was shipped once and was wrong). What is accurate is the per-file fraction the Hub computes from `URLSession`'s byte counts, so `HuggingFaceDownloader` asks the Hub API for every matching file's size and then calls `snapshot` **per filename**, weighting each file's own fraction by its real size. Don't "simplify" this back to one `snapshot` call over all patterns, and don't poll the directory. `AICoachDownloadProgress` also carries a smoothed `bytesPerSecond` (`ByteRateMeter`, surfaced through `Progress`'s `throughputKey`) so the card can show a rate and a time remaining — on a slow connection that line, not the bar, is what distinguishes slow from hung.
- **`isHuggingFaceRepoCached` must not check `config.json` alone** — it is a few hundred bytes and lands in the first second of a multi-gigabyte download, so an interrupted download would report itself cached and then fail to load. It requires weights present (a `.safetensors` file only appears once fully transferred, per the staging note above) *and* no leftover `.incomplete` partial.
- **AI model delivery**: Gemma 4 E2B 4-bit weights (~4.3 GB) are **not bundled** — they download from Hugging Face on first use and are cached locally for offline access. mlx-swift-lm 3.x dropped its bundled Hub integration, so `Packages/AICoachRuntime/Sources/AICoachRuntime/ModelLoading.swift` supplies the `Downloader` / `TokenizerLoader` conformances over swift-transformers' `HubApi` and `AutoTokenizer`, plus an adapter bridging its `Tokenizer` to `MLXLMCommon`'s own copy. `CoachModelPreset.toolCallFormat` and `extraEOSTokens` must match the model family (`"gemma4"` + `<turn|>` today; Gemma 3 used `"gemma"` + `<end_of_turn>`).
- **Conditional compilation**: All MLX-specific code (in `Packages/AICoachRuntime`) is gated behind `#if canImport(MLXLLM)`. The `#else` branches throw `CoachRuntimeError.runtimeUnavailable`.
- **Voice entry to the coach**: the Home mic button (`home.coachVoiceButton`) pushes the chat with `entry: .voice(autoSend: false)`, arming dictation on appear. Dictation runs through the `CoachSpeechService` protocol — `LiveCoachSpeechService` over SFSpeechRecognizer (on-device where supported) and `StubCoachSpeechService` for previews/tests/UI tests — injected via `@Environment(\.coachSpeech)` with the stub as the default, and the stub injected at the app root under `-uiTestSeed`. The mic is gated on `CoachModelPhase.isUsable` exactly like the coach card; while the weights are missing it sits greyed out beside a slim CTA (`home.coachVoiceDownloadCTA`) that deep-links to the chat's download prompt. Dictated text merges into typed text via the pure `VoiceDraft.compose` helper; usage descriptions live in `Info.plist` (`NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription`).
- **Widget + Siri entry to the coach.** A widget can never use the mic, so `CoachVoiceWidget` (extension target, Home + Lock Screen) is only a `widgetURL` to `com.bradlet.train://coach/voice`; Siri's `AskCoachIntent` ("Tell my AI coach") transcribes before opening the app, and `TalkToCoachIntent` mirrors the widget. All of them route a `CoachChatEntry` through `CoachLaunchRouter.shared` (`@Environment(\.coachLauncher)`), and `HomeView` (value-based `NavigationStack(path:)`) replaces the stack with that chat. Only these external entries auto-send, via the pure `VoiceAutoSend` rules (1.5 s pause after speech, 8 s with nothing heard gives up, wait for `.ready`); the in-app mic stays review-then-send, and **nothing auto-downloads the model**. Every App Shortcut phrase needs `\(.applicationName)`, so `INAlternativeAppNames` ("AI Coach", "Coach") makes it sayable. The widget hardcodes its URL, and `CoachLaunchRouteTests` pins the literal.
- **Google Sheets Sync**: `GoogleSheetsSyncCoordinator` (`@MainActor @Observable`) debounces workout mutations and exports via the `GoogleSheetsAPI` protocol (`LiveGoogleSheetsAPI` uses GoogleSignIn-iOS + URLSession behind `#if canImport(GoogleSignIn)`; `StubGoogleSheetsAPI` for previews/tests). Injected via `@Environment(\.googleSheetsSync)`. Uses the **`auth/drive.file` scope** (per-file access only — non-sensitive, no Google verification needed); never `auth/spreadsheets`. OAuth client, GCP project script (`scripts/gcp/bootstrap.sh`) and Info.plist setup are documented in `docs/CONNECTIONS.md`.

## Testing Requirements

**Every new feature must ship with unit tests. This is non-negotiable.**

- New model fields → test default value, explicit set, and SwiftData persistence.
- New service/logic types → test all public methods and edge cases (empty inputs, boundary values).
- New prompt/serialization logic → test each output field, metric/imperial variants, omission conditions.
- Prompt builder tests live in `Packages/AICoachCore/Tests/AICoachCoreTests/PromptBuilderTests.swift`.
- App-level tests live in `TrainTests/TrainTests.swift`, grouped by `struct` with a `// MARK:` header.
- Functional UI tests for multi-step flows live in `TrainUITests/` using `XCTest` + `XCUIApplication` (UI tests stay on XCTest because Swift Testing doesn't integrate with XCUI). They launch the app with `-uiTestSeed` to install an in-memory container + deterministic fixtures via `Config/UITestFixtures.swift`. Add new identifiers via `.accessibilityIdentifier(...)` when introducing testable controls.
- SwiftData tests that touch a `ModelContext` should use `ModelContext(container)` rather than `container.mainContext` — `mainContext` is `@MainActor`-isolated and crashes under Swift Testing's parallel execution.
- Do not ship a feature without at least one test per public method.

## Conventions
- Swift Testing framework (not XCTest) — use `@Test`, `#expect()`, `import Testing`
- Header doc comments on all public/internal functions
- `ModelContainerFactory.makePreviewContainer()` for test and preview contexts
- Cached `DateFormatter` instances (static lets) — never allocate in computed properties
- **The strength board never changes the selected day in response to a move.** Dragging a card onto a day chip and the card's "Move to Day" context menu both leave `selectedDay` alone; the chip counts are the feedback. Don't "helpfully" follow the exercise.
- **Favorites pre-fill, they never record.** A `FavoriteWorkout` fills only name, type, targets and counts-toward-mileage; date, notes, ratings and recurrence stay as the athlete set them. Every favorite ↔ form conversion goes through `FavoriteFormValues` and every mutation through `FavoriteWorkoutEditor`. Sheets receive `favorites` as a `let` from `HomeView`/`AerobicTrainingView` — they never query.
- **Plan editing goes through `StrengthPlanFields`/`StrengthPlanDraft`.** Any surface that sets `plannedSets`/`plannedReps` (add-from-library today) reuses that section so the add and edit flows can't drift apart.
- **Sheets sync `syncNow()` vs `performSync()` must stay split.** The debounce `Task` calls `performSync()` directly. Calling `syncNow()` from inside the debounce task would `.cancel()` the task on itself, propagating cancellation to the in-flight `URLSession` and surfacing as `CancellationError("cancelled")`. `StubGoogleSheetsAPI.overwriteSheet` calls `Task.checkCancellation()` to catch regressions of this pattern.

## File Layout
```
Packages/
  AICoachCore/     Shared library: prompt builder, coaching types, formatters, GenerationConfig
  AICoachRuntime/  Model runtime (MLX): preset, CoachRuntime, Hugging Face loading
Evals/           AI coach evals: CoachEvalKit + coach-eval CLI (real model on Metal)
CoachVoiceWidget/  WidgetKit extension: "talk to your coach" deep-link widget
Models/          Data models and enums
Config/          ModelContainer, environment keys (units, aiCoach), UITestFixtures
Extensions/      Date+Week, Double+Distance (distance, duration, pace formatting)
Services/
  AICoach/          Coach protocol, MLX adapter, stub, chat store, proposal applier, speech-to-text, type conversions
  ExercisePlanner/  Recurring series generation + bulk CRUD
  ExerciseLibrary/  Strength exercise library providers
  GoogleSheetsSync/ Google Sheets export
  HealthKitImport/  Apple Health import
  WorkoutCSV/       CSV import/export
Views/
  Home/             Home tab (today's training, quick record, coach chat)
  AerobicTraining/  Training tab
  History/          History tab (calendar, workout list, detail sheet)
  Strength/         Strength tab
  Settings/         Preferences (units, week start)
  Shared/           Cross-tab building blocks (e.g. WorkoutFormFields)
```

## Key Files
- `Packages/AICoachCore/Sources/AICoachCore/AICoachPromptBuilder.swift` — stateless prompt serialization (shared by app + evals)
- `Packages/AICoachCore/Sources/AICoachCore/GenerationConfig.swift` — single source of truth for LLM generation parameters
- `Config/ModelContainerFactory.swift` — single place for container/CloudKit config
- `Config/AICoachEnvironment.swift` — `@Environment(\.aiCoach)` key; default is `StubAICoachService`
- `Config/UITestFixtures.swift` — deterministic fixture seed activated by `-uiTestSeed` launch arg
- `Extensions/Date+Week.swift` — all calendar arithmetic
- `Extensions/Double+Distance.swift` — distance, duration, and pace formatting (`Int.formattedPace(distanceMiles:metric:)` for min/mile and min/km)
- `Models/ExerciseType.swift` — exercise type enum with icons and colors
- `Models/ExerciseSeriesSpec.swift` — Codable spec for a recurring exercise series (cadence, inclusive end date, every-N-occurrences progression)
- `Services/ExercisePlanner/SeriesGenerator.swift` — pure spec → dated occurrences expansion (monthly anchored to start date, 400-occurrence cap)
- `Services/ExercisePlanner/ExercisePlanner.swift` — bulk CRUD for series-tagged exercises (`seriesID`). Scoped to *series* mutations; a coach proposal targets one session on one day and so mutates it directly via `CoachProposalApplier` (which calls `detach` before removing a series member). Recurring plans are eager bulk inserts of concrete `Exercise` rows — there are no templates or virtual instances.
- `Services/AICoach/AICoachService.swift` — protocol + `AICoachError` enum
- `Services/AICoach/MLXAICoachService.swift` — production coach: thin `AICoachService` adapter over `CoachRuntime` (20 MB MLX cache cap)
- `Packages/AICoachRuntime/Sources/AICoachRuntime/CoachModelPreset.swift` — the model: swap it via `CoachModelPreset.production`
- `Packages/AICoachRuntime/Sources/AICoachRuntime/CoachRuntime.swift` — load + generate → tool call → `CoachEvent`; shared by app and evals
- `Packages/AICoachRuntime/Sources/AICoachRuntime/ModelLoading.swift` — Hugging Face downloader (byte-weighted progress), tokenizer loader, tokenizer adapter, and the cached-weights check
- `Evals/Sources/CoachEvalKit/Scenarios/` — eval scenarios (one file per area) and shared `Fixtures`; see `docs/EVALS_GUIDE.md`
- `Services/AICoach/CoachChatStore.swift` — ephemeral (session-scoped) conversation state; `@Environment(\.coachChat)`
- `Services/AICoach/CoachLaunchRoute.swift` — `CoachChatEntry`, deep-link parse/build, `CoachLaunchRouter` (unit-tested)
- `Services/AICoach/CoachIntents.swift` — `AskCoachIntent`, `TalkToCoachIntent`, `CoachShortcuts` Siri phrases
- `CoachVoiceWidget/CoachVoiceWidget.swift` — Home/Lock Screen widget extension (deep link only)
- `Services/AICoach/CoachSpeechService.swift` — speech-to-text protocol + `VoiceDraft` draft-merge helper + `VoiceAutoSend` hands-free rules; `LiveCoachSpeechService` wraps SFSpeechRecognizer, `StubCoachSpeechService` keeps tests off the microphone; `@Environment(\.coachSpeech)`
- `Services/AICoach/CoachProposalApplier.swift` — applies accepted proposals; typed failures, no invented sessions (unit-tested)
- `Services/AICoach/CoachTypeConversions.swift` — SwiftData ↔ AICoachCore type bridge
- `Packages/AICoachCore/Sources/AICoachCore/CoachTools.swift` — tool vocabulary + proposal payloads
- `Packages/AICoachCore/Sources/AICoachCore/CoachToolSchemas.swift` — JSON schemas (no MLX import)
- `Packages/AICoachCore/Sources/AICoachCore/CoachToolDecoding.swift` — validating decoder for raw tool calls
- `Views/Home/HomeView.swift` — Home tab; owns the queries and builds the coach's training snapshot
- `Views/Home/TodayTraining.swift` — pure day selection for Home (unit-tested)
- `Views/Home/CoachChatView.swift` — the conversation: bubbles, composer, proposal cards
- `Services/GoogleSheetsSync/GoogleSheetsSyncCoordinator.swift` — debounce + lifecycle + `GoogleSheetsSyncStatus` enum
- `Services/GoogleSheetsSync/GoogleSheetsAPI.swift` — protocol + Live (GoogleSignIn + URLSession) + Stub implementations
- `Views/Shared/WorkoutFormFields.swift` — reusable workout form sections shared by `RecordWorkoutSheet` (create) and `WorkoutDetailSheet` (edit)
- `Views/Shared/RadialRatingPicker.swift` — the radial dial, plus the configured `FeelingDial` (1–5, faces) and `ExertionDial` (1–10, numerals)
- `Views/Shared/RadialDialGeometry.swift` — pure drag → position → snapped-slot math for the dial (unit-tested)
- `Views/Shared/RatingVisuals.swift` — `FeelingVisuals` / `ExertionVisuals`: display names, face symbols, and the two tint ramps
- `Views/History/WeeklyChartSegments.swift` — splits weekly points into contiguous runs so the chart line breaks across weeks with no data (unit-tested)
- `Views/History/CalendarDayDot.swift` — resolves a calendar day's dot to none/solid/hollow from its items' `countsTowardTraining` (unit-tested)
- `Views/History/WorkoutDetailSheet.swift` — edit + delete popup for a recorded workout; contains the `WorkoutEditor` helper enum that owns the mutation path (unit-tested)
- `Views/History/WorkoutListView.swift` — discrete 10-per-page pagination, tappable rows, calendar-driven navigation/highlight, `WorkoutListPagination` helper for testable page math
- `Models/FavoriteWorkout.swift` — saved aerobic preset (`@Model`), plus `targetSummary(metric:)`
- `Services/Favorites/FavoriteWorkoutEditor.swift` — `FavoriteFormValues` (stored ↔ form units, planned-first Save-as seed) and `FavoriteWorkoutEditor` (make/update/delete/reorder) (unit-tested)
- `Views/Home/FavoritesSection.swift` / `ManageFavoritesSheet.swift` / `FavoriteWorkoutFormSheet.swift` — Home favorites card, manager, and create/edit form
- `Views/Shared/FavoriteMenuSection.swift` — "Start from Favorite" menu shared by `RecordWorkoutSheet` and `AddExerciseSheet`
- `Views/Strength/StrengthBoardPlanner.swift` — pure lane/order mutations for the weekly kanban board (unit-tested)
- `Views/Strength/StrengthPlanFields.swift` — `StrengthPlanDraft` (plan form state + `apply(to:)`) and the shared sets × reps form section used by both the add-from-library and edit-plan flows
- `Views/Strength/ExerciseLibrarySheet.swift` — library browser: muscle-group filter chips + search + sectioned list, plus the `ExerciseLibraryFilter` helper enum owning the filter/grouping math (unit-tested)
