# Run-Aware Placement — Fitting Strength Around the Cardio Week (design draft)

> Status: **design draft**, iteration 3 (2026-11-24). Realises idea S1 from [STRENGTH_IDEAS.md](STRENGTH_IDEAS.md).
> Shares its rule engine with the Home hybrid hints (roadmap H2, issue #19).

## The idea

The strength board knows the athlete's cardio week and helps place lifting days around it. Lower-body work stacks on the days the athlete marked as key workouts (key workout first) and stays off the day before them, which keeps easy days easy. It's guidance, never an automatic change.

**Evidence and opinion:**
- **Spacing:** interference with strength gains appears mainly when the two are done close together: under about 20 minutes in one meta-analysis ([PMC8053170](https://pmc.ncbi.nlm.nih.gov/articles/PMC8053170)) and under 3 hours in another ([Examine](https://examine.com/research-feed/study/1PQaW0)).
- **Coaching consensus** is to stack lower-body strength on hard-run days, with the run first and the two hours apart, and to avoid heavy legs the day before key sessions ([Outside](https://run.outsideonline.com/training/cross-training/how-to-lift-and-run-without-wrecking-either/), [TrainingPeaks](https://trainingpeaks.com/blog/risks-of-concurrent-training/)). Some coaches dissent, so the rules are opinionated defaults with the reasoning shown.

## Decisions

| Topic | Decision |
|---|---|
| What "Arrange my week" moves | **Whole days.** Lanes move between weekdays intact, so leg day stays one day. Days can be **pinned**. |
| Authority | Suggestions only. Nothing moves without an explicit Accept, and every arrangement can be undone. |
| Key-day strategy | A **global preference the athlete chooses** in Settings → Training, also switchable from the Arrange sheet: **Stack strength with key days** ("hard days hard", the default until changed) or **Keep key days lift-free**. |
| What counts as hard | **Entirely the athlete's call.** A workout is a *key* (hard) workout only if the athlete marked it as one. The app never infers hardness from type, distance, pace, or RPE, and every hard-workout analysis respects their marking. |

## Inputs and classification

**Reference week:** the current week (by the week-start setting), using planned and recorded `Exercise`s. A *This week / Next week* toggle sits in the Arrange sheet. When a training plan is active, its base week is used ([TRAINING_PLANS.md](TRAINING_PLANS.md)).

**Key workouts are athlete-defined.**
- **A `Key workout` toggle** (⚡) sits on every cardio session: in the add/edit planning sheets, in the record sheet, and on favorites, so a favorite pre-fills it like its other targets. It's stored as `Exercise.isKeyWorkout: Bool = false`.
- **Per-type defaults are the athlete's own.** Settings → Training → *Key workouts by default* lists exercise types with nothing selected, and the athlete ticks whichever types they treat as hard (e.g. Tempo Run, Interval Run, Long Run). New sessions of a ticked type start with the toggle on, and the per-session toggle always wins.
- **Training plans** carry the flag on each cardio prescription, so a preset can mark its key sessions and the athlete can change them.
- **No inference, anywhere.** Placement, Home hybrid hints, and week-strip markers read only `isKeyWorkout`. If nothing is marked, the placement rules have no key days and stay quiet.

**Cardio days** are classified from those flags:

| Class | From |
|---|---|
| **Key** | at least one session that day marked ⚡ key |
| **Easy** | cardio, none of it marked key |
| **Rest** | no cardio |

**Strength lanes** are classified by load:
- **Lower-heavy** if the lane holds any squat, hinge, single-leg, or lower-body power card. This uses the movement pattern ([MOVEMENT_GROUPS.md](MOVEMENT_GROUPS.md)) and falls back to the quads, hamstrings, glutes, or full-body muscle group.
- **Upper/core** otherwise.

**Placement table for a lower-heavy lane:**

| Day | Verdict | Why shown |
|---|---|---|
| Key day, strategy **Stack** | ✅ **Stack** | "Hard days hard: do the key workout first, lift 3+ h later if you can" |
| Key day, strategy **Lift-free** | ⚠️ Avoid | "You keep key days lift-free" |
| Easy day, next Key day ≥ 2 days away | ✅ Good | — |
| Easy or Rest day **before** a Key day | ⚠️ Avoid | "Heavy legs the day before your key workout" |
| Rest day, nothing key next | ◻︎ Neutral | Rest days are best left as rest |

Upper/core lanes are ✅ anywhere, with a mild preference for easy days. Two lower-heavy lanes less than 48 hours apart get a soft ⚠️. A light week ([TRAINING_PLANS.md](TRAINING_PLANS.md)) softens every ⚠️ to a note.

## Surfaces

1. **Cardio markers on day chips, always.** A tiny glyph under each Strength day chip shows that day's cardio class: `⚡` key, `•` easy, or blank for rest. Planning strength means seeing the runs.
2. **Drag tint.** While dragging a lower-heavy card, chips tint green (✅), amber (⚠️), or neutral. This is the cheapest, most direct form of the feature.
3. **Lane conflict badge.** A lane in a ⚠️ spot shows `⚠︎ Day before long run` in its header. Tapping it gives a one-line explanation with **Arrange my week** and **Dismiss for this week** (the same dismissal model as the hybrid hints).
4. **Arrange my week** (from the badge, or from the board toolbar's ⋯ menu):

   ```
   ARRANGE MY WEEK            This week ▾
   Before   Su  Mo  Tu  We  Th  Fr  Sa
   Run      --  5   --  6⚡ --  4   14⚡
   Lift     --  UB  --  --  LB! --  --
   After
   Lift     --  UB  --  LB  --  --  --
   • Move Lower Body: Thu → Wed (stack on key day)
                     [Cancel]  [Apply]
   ```

   - **Algorithm:** brute-force every lane-to-weekday permutation with pinned days fixed (at most 7! = 5,040, which is trivial). Cost = weighted conflicts + a spacing penalty + **one point per moved lane**, so the smallest fix wins.
   - **If nothing improves:** "Your week already works", with no proposal. If no workout is marked key, the sheet says so and links to *Key workouts by default*.
   - **Apply** moves lanes through `StrengthBoardPlanner`, then shows an **Undo** toast. The board stays on the selected day, in line with the existing "never follow a move" rule.
5. **Pinning.** Long-press a day chip and choose **Pin Thursday's plan**, for when the gym is only available on certain days. Arrange never moves a pinned lane.
6. **Same-day cue on Home** (Stack strategy only). On a day with both a key workout and a lower-heavy lane, Today shows "Run first, lift later if you can" once. It never nags.
7. **When cardio changes** (a key workout moves, or a session is marked or unmarked as key), affected lanes simply pick up or lose their badges. Nothing auto-moves.

## Implementation notes

- **One rule engine.** A pure `HybridDayClassifier` plus `PlacementRules` feed the Home hybrid hints (#19), the chip tints, the badges, and the arranger. All are unit-tested over fixture weeks.
- **The arranger** is a pure `WeekArranger.propose(lanes:cardio:pinned:)`, which returns moves plus a before/after cost.
- **Pinned weekdays**, **key-by-default types**, and the **key-day strategy** (`keyDayStrategy: stack | liftFree`, a plain raw-value enum stored as a String) are stored as small JSON `Data` fields on `AppConfiguration`, following the CloudKit defaults rule.
- **New model field:** `Exercise.isKeyWorkout: Bool = false`, which needs tests for its default, explicit set, and persistence. It's also added to `FavoriteFormValues` (favorites pre-fill it) and to the CSV/Sheets columns via the connections layer.

## Open questions

1. ~~Long key sessions?~~ **Decided:** a global key-day strategy the athlete chooses (stack strength with key days, or keep key days lift-free). No per-session override for now.
2. **Should the same-day "key workout first" cue appear on the board too, or only on Home?**
3. **Should past *recorded* sessions keep the key flag they were planned with,** for later "key workouts per week" stats in Progress?
