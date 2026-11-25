# Done as Planned — One-Tap Strength Logging (strength only) (design draft)

> Status: **design draft**, iteration 2 (2026-11-24). Realises idea S4 from [STRENGTH_IDEAS.md](STRENGTH_IDEAS.md).
> Builds on fast recording (#14) and the weekly loop (#15).

## The idea

Most strength days go roughly to plan. With one number per lift and no per-set logging, a whole day can be recorded in **one tap**, and the athlete adjusts only the exceptions. This targets the most common complaint about logging apps: too many taps, and no prefill ([Setgraph roundup](https://setgraph.app/ai-blog/best-workout-tracker-app-reddit)).

## Decisions

| Topic | Decision |
|---|---|
| Scope | **Strength only.** It never records cardio, and its label and placement have to make that unmistakable. |
| Cardio stays separate | Runs keep their existing quick completion: the per-card record action on each `ExerciseCardView` in Today. Nothing about that flow changes, and the two must never look like one action. |
| Surfaces (now) | A **Home Today** strength section button and a **board day** button. |
| Deferred | Interactive widget, Live Activity, and a Siri/Shortcuts App Intent. These weren't chosen this round and are listed at the end. |

## Where it appears

```
HOME · TODAY
🏋 STRENGTH                  [🏋 Log lifts as planned]
  Back Squat         3×5   185 lb
  Chest Press ⟳  → Incline DB  55 lb
  Single-Leg ⟳   → Reverse Lunge  ✓ done
```

(Cardio cards sit above this section with their own per-card record buttons, unchanged.)

- **Home:** a button in the header of Today's **Strength** section, shown when at least one active card for today is unrecorded.
  - **Label:** "**Log lifts as planned**" with the dumbbell glyph, so it's never a generic "Done". The toast reads "Logged 4 lifts".
  - **Placement:** in the Strength sub-header, beneath the cardio cards and visually attached to the lift rows. Today the "Strength" sub-header only appears when cardio is also present. It now **always** appears when the button does, so the button can never sit near the Today header or the run cards.
  - **No day-level "complete today" control** covers both disciplines. Cardio cards keep their own per-card record action, unchanged.
  - **UI test:** asserts that the button lives inside the strength section and that tapping it leaves every cardio card's state untouched.
- **Board:** the same button in the day column's Plan header. It applies to the viewed weekday of the **current week**:
  - **today:** recorded with today's date
  - **an earlier day this week:** backfilled to that day's date, with the button reading "Done as planned · Tue"
  - **a future day:** the button is hidden

## What one tap records

For every **active, unrecorded** card in the lane, in board order:

| Field | Value |
|---|---|
| Lift | The card's lift; for a group, its **up-next** member ([MOVEMENT_GROUPS.md](MOVEMENT_GROUPS.md)) |
| Value | The card's **target** if planned ([TRAINING_PLANS.md](TRAINING_PLANS.md)), else that lift's **last value**, else **no value** ("done") |
| Measurement | The lift's default measurement |
| `slotID` | The card |
| Date | As above |

- **Skipped:** cards already recorded today, offloaded cards, and missed lifts carried over from earlier days. Carryover stays its own explicit action.
- **Feedback:** a toast reading `Logged 4 lifts · Undo · Adjust`.
  - **Undo** removes exactly the records just created.
  - **Adjust** opens the whole-day sheet (#14) with those records loaded, so one weight can be nudged or one lift unticked.
- **"Done as planned, except…":** long-press the button to open the whole-day sheet with every lift pre-ticked and prefilled. Untick what you skipped, nudge what changed, and save.
- **PR badges** (#15) still fire if a recorded value beats a lift's best, though by definition that's rare from plan values.

## Relationship to the whole-day sheet

"Done as planned" is the **express path** of the same sheet. The sheet carries the same button at the top, so both paths produce identical records through one pure helper.

## Implementation notes

- A pure, unit-tested `PlannedDayLogger.records(lane:on:records:targets:groups:)` returns the `StrengthWorkout`s to append, one per card. Undo is the inverse, by record id.
- No new model fields are needed beyond those in #13 (lift-owned history, optional value, `slotID`).
- A UI test should cover: tap on Home → toast → Undo leaves the board unchanged, and tap → Adjust → edit one weight → saved.

## Deferred surfaces (revisit later)

- **Interactive widget:** today's lifts as a checklist, tap a row to record it at plan values. This needs the SwiftData store in an App Group so the widget extension can write to it.
- **Live Activity:** a lifting session on the Lock Screen and Dynamic Island showing the next lift and its target, tap to tick. It would also capture session duration, which feeds the hybrid load idea (S3).
- **Siri / Shortcuts / Action button:** an App Intent, "Log my lifts as planned", independent of the coach.

## Open questions

1. When a card has **no target and no history**, should one tap still record a value-less "done", or should it skip the card and say so in the toast? Proposal: record "done", since bodyweight and new lifts count too.
2. ~~Cover today's cardio too?~~ **Decided: no.** It's strength only, and the cardio quick completion stays a separate, clearly distinct flow.
