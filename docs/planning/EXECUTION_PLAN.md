# Execution Plan

One ordered path through everything planned on 2026-11-24. Do one step at a time. Each step is an issue that ships as small conventional commits and leaves the app building. The detail lives in the linked docs and issues.

**Guiding rules:** the Product Vision in `CLAUDE.md` (hybrid by default, low friction, the athlete decides what's hard, strength and cardio quick actions stay distinct). The AI coach is out of scope.

## Plan

### A. Rebrand and infrastructure
1. ✅ **#27** Scripted GCP project and new Google OAuth client, with the consent screen published to production.
2. ✅ **#11** Rebrand to **Train** (*Train: Built to Endure*, [ADR 2](../adrs/2-rebrand-to-train.md)), following its phases in order:
   1. brand discussion and ADR
   2. rename locally
   3. rename the repo
   4. publish to App Store Connect and TestFlight
   5. decommission the old app and repo

   CloudKit is now on (development only). Deploying the *production* schema and checking two-device sync is **#30**. Production schemas can only be added to, so the model changes in #13 should land before #30.

### B. Foundation
3. **#12** App structure: Home · Cardio (Plan | Progress) · Strength (Plan | Progress). History becomes Cardio → Progress. Docs: [README](README.md), [PROGRESS_VIEWS](PROGRESS_VIEWS.md)
4. **#13** Lift-owned history, a metric per lift, and records linked to the card they were logged from (`slotID`). Doc: [STRENGTH_ROADMAP](STRENGTH_ROADMAP.md) §1

### C. Daily strength loop
5. **#14** Fast recording: prefill, per-lift measurement, the whole-day sheet, "done" with no number. Doc: [STRENGTH_ROADMAP](STRENGTH_ROADMAP.md) §2
6. **#15** Current-week checkmarks, missed-lift carryover, PR badge. Doc: [STRENGTH_ROADMAP](STRENGTH_ROADMAP.md) §3
7. **#26** "Log lifts as planned" in one tap, strength only. Doc: [DONE_AS_PLANNED](DONE_AS_PLANNED.md)
8. **#24** Movement groups: smart rotation, with a toggle for one member per block. Doc: [MOVEMENT_GROUPS](MOVEMENT_GROUPS.md)

### D. Progress
9. **#16** Strength → Progress: lift list, lift detail, PRs. Doc: [STRENGTH_ROADMAP](STRENGTH_ROADMAP.md) §4
10. **#17** Cardio → Progress refactor: training-inclusion opt-in and scoped views. Doc: [PROGRESS_VIEWS](PROGRESS_VIEWS.md)

### E. Hybrid planning
11. **#18** Muscle-balance glance and copy day / duplicate card. Doc: [STRENGTH_ROADMAP](STRENGTH_ROADMAP.md) §5
12. **#25** Run-aware placement: the athlete-marked ⚡ key flag, the key-day strategy (stack or lift-free), and "Arrange my week". Doc: [RUN_AWARE_PLACEMENT](RUN_AWARE_PLACEMENT.md)
13. **#19** Home hybrid hub: week strip and dismissible hints, reusing the rule engine from step 12. Doc: [STRENGTH_ROADMAP](STRENGTH_ROADMAP.md) §6

### F. Training plans
14. **#20** Generic plans (steady ↔ program, cardio, strength, hybrid, presets). This absorbs **#10**. Resolve the doc's §9 open questions first. Doc: [TRAINING_PLANS](TRAINING_PLANS.md)

### G. Connections
This is an independent track. It can run in parallel with any step after step 4, because it needs the strength record format.

15. **#21** Generic import/export layer, covering strength. Doc: [CONNECTIONS](CONNECTIONS.md)
16. **#23** Connections dashboard, sync status, CSV auto-export. Doc: [CONNECTIONS](CONNECTIONS.md)
17. **#22** Garmin import: FIT files first, the API later. Doc: [CONNECTIONS](CONNECTIONS.md)

### H. Next brainstorm
18. **Pick the next ideas** from [STRENGTH_IDEAS](STRENGTH_IDEAS.md): S8 self-maintaining board, S2 priority trim, S6 longevity check-ins, S7 power, S3 hybrid load. Design each one, then file an issue for it.

## Dependencies

```mermaid
flowchart LR
    I27["#27"] --> I11["#11 Train"]
    I11 --> I12["#12 IA"] & I13["#13 lift history"]
    I13 --> I14["#14"] --> I15["#15"] --> I26["#26"]
    I13 --> I24["#24 groups"] --> I26
    I12 & I13 --> I16["#16"]
    I12 --> I17["#17"]
    I13 --> I18["#18"]
    I24 --> I25["#25 placement"] --> I19["#19 hub"]
    I15 --> I19
    I19 --> I20["#20 plans"]
    I13 --> I21["#21 connections"] --> I23["#23"] & I22["#22"]
```
