//
//  StrengthTrainingView.swift
//  Train
//
//  Strength → Plan: a kanban-style weekly board. Hosted by `StrengthView`,
//  which owns the navigation bar. One
//  column per day (Sunday-Saturday), swipeable left/right like a project
//  management board. Each column has the day's active plan plus a lower
//  "offloaded" section for exercises kept in mind but out of the week's plan.
//  Exercises are undated slots for lifts; recorded sessions
//  (`StrengthRecord`) belong to the lift and carry dates.
//

import SwiftUI
import SwiftData

/// The strength training tab displaying the weekly kanban board.
struct StrengthTrainingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.weekStartDay) private var weekStartDay
    @Query private var allExercises: [StrengthExercise]
    @Query private var allRecords: [StrengthRecord]
    @Query(sort: \UserMovementGroup.createdAt) private var userGroups: [UserMovementGroup]

    /// The day column currently shown (Sunday=0 ... Saturday=6).
    @State private var selectedDay: Int = Date().weekdayIndex
    /// Whether the exercise library sheet is presented.
    @State private var showLibrary = false
    /// The weekday lane being logged in the whole-day sheet (nil = hidden).
    @State private var loggingDay: LogStrengthDayRequest?
    /// The last one-tap "as planned" log, while its toast shows.
    @State private var plannedLog: PlannedDayLogResult?
    /// The card a session is being recorded from (nil = sheet hidden).
    @State private var recordingExercise: StrengthExercise?
    /// The group editor, for "Edit Group" / "Make This a Group" (#24).
    @State private var groupEdit: SlotGroupEdit?
    /// The "New best" banner after a save beats a lift's best.
    @State private var newBest: NewBestAnnouncement?

    var body: some View {
        let latestRecords = StrengthLiftRegistry.latestByLiftKey(allRecords)
        let weekRecords = StrengthWeek.recordsBySlot(allRecords, now: Date(), firstWeekday: weekStartDay)
        let groups = movementGroups
        let assignments = GroupRotation.assignments(
            slots: allExercises, groups: groups, records: allRecords, now: Date(), firstWeekday: weekStartDay
        )
        VStack(spacing: 0) {
            dayStrip
            Divider()
            TabView(selection: $selectedDay) {
                ForEach(0..<7, id: \.self) { dayIndex in
                    StrengthDayColumn(
                        dayIndex: dayIndex,
                        allExercises: allExercises,
                        latestRecords: latestRecords,
                        weekRecords: weekRecords,
                        assignments: assignments,
                        onGroup: { slot in groupEdit = SlotGroupEdit(slot: slot, groups: groups) },
                        onRecord: { recordingExercise = $0 },
                        onAddExercise: { showLibrary = true },
                        onLogDay: {
                            // Dated to that weekday's most recent occurrence,
                            // so earlier days this week can be backfilled.
                            loggingDay = LogStrengthDayRequest(
                                slots: StrengthBoardPlanner.lane(allExercises, day: dayIndex, offloaded: false),
                                date: Date().mostRecent(weekdayIndex: dayIndex)
                            )
                        },
                        asPlanned: asPlannedAction(for: dayIndex),
                        onDrop: { id, offloaded, target in
                            handleDrop(id: id, day: dayIndex, offloaded: offloaded, target: target)
                        },
                        onMoveToDay: { exercise, day in
                            moveToDay(exercise, day: day)
                        },
                        onDelete: { exercise in
                            withAnimation { modelContext.delete(exercise) }
                        }
                    )
                    .tag(dayIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showLibrary = true
                } label: {
                    Label("Exercise Library", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("strength.libraryButton")
            }
        }
        .sheet(isPresented: $showLibrary) {
            ExerciseLibrarySheet(
                provider: .withUserLibrary(container: modelContext.container),
                onSelect: { entry, plan in addFromLibrary(entry, plan: plan) },
                onSelectGroup: { group, plan in addGroup(group, plan: plan) }
            )
        }
        .sheet(item: $groupEdit) { edit in
            MovementGroupEditorSheet(
                group: edit.group,
                title: edit.slot.isGroup ? "Edit Group" : "Make a Group",
                provider: .withUserLibrary(container: modelContext.container)
            ) { group in
                if edit.slot.isGroup {
                    MovementGroupStore.save(group, in: modelContext)
                } else {
                    MovementGroupStore.assign(group, to: edit.slot, in: modelContext)
                }
            }
        }
        .sheet(item: $recordingExercise) { exercise in
            RecordStrengthSheet(slot: exercise) { newBest = NewBestAnnouncement(liftNames: $0) }
        }
        .sheet(item: $loggingDay) { request in
            LogStrengthDaySheet(
                slots: request.slots,
                date: request.date,
                startTicked: request.startTicked
            ) { newBest = NewBestAnnouncement(liftNames: $0) }
        }
        .newBestBanner($newBest)
        .plannedLogToast($plannedLog, onUndo: undoPlannedLog, onAdjust: adjustPlannedLog)
    }

    // MARK: - Done as planned (#26)

    /// The lane's "Done as planned" button, or `nil` to hide it: a day
    /// still to come this week, or nothing left to log that day.
    private func asPlannedAction(for dayIndex: Int) -> StrengthDayColumn.AsPlannedAction? {
        let now = Date()
        guard let date = PlannedDayLogger.logDate(forLane: dayIndex, now: now, firstWeekday: weekStartDay) else {
            return nil
        }
        let lane = StrengthBoardPlanner.lane(allExercises, day: dayIndex, offloaded: false)
        guard !PlannedDayLogger.pending(lane, on: date, records: allRecords).isEmpty else { return nil }
        let isToday = Calendar.current.isDate(date, inSameDayAs: now)
        return StrengthDayColumn.AsPlannedAction(
            title: isToday ? "Done as planned" : "Done as planned · \(Calendar.current.shortWeekdaySymbols[dayIndex])",
            log: {
                guard let result = PlannedDayLogger.log(lane, on: date, in: modelContext, firstWeekday: weekStartDay) else { return }
                plannedLog = result
                if !result.newBests.isEmpty { newBest = NewBestAnnouncement(liftNames: result.newBests) }
            },
            logWithChanges: {
                loggingDay = LogStrengthDayRequest(
                    slots: PlannedDayLogger.pending(lane, on: date, records: allRecords),
                    date: date,
                    startTicked: true
                )
            }
        )
    }

    /// Removes the records a one-tap log wrote.
    private func undoPlannedLog(_ result: PlannedDayLogResult) {
        withAnimation { PlannedDayLogger.undo(result, in: modelContext) }
    }

    /// Swaps a one-tap log for the whole-day sheet, pre-ticked with the
    /// same values, so one lift can be nudged or unticked.
    private func adjustPlannedLog(_ result: PlannedDayLogResult) {
        PlannedDayLogger.undo(result, in: modelContext)
        loggingDay = LogStrengthDayRequest(
            slots: result.slotIDs.compactMap { id in allExercises.first { $0.id == id } },
            date: result.date,
            startTicked: true
        )
    }

    // MARK: - Day Strip

    /// Tappable Sun-Sat chips above the board. Each chip is also a drop
    /// target, so a card can be dragged onto a chip to move it to that day.
    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { dayIndex in
                dayChip(dayIndex)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// One day chip with the short weekday name and planned-exercise count.
    private func dayChip(_ dayIndex: Int) -> some View {
        let isSelected = selectedDay == dayIndex
        let isToday = Date().weekdayIndex == dayIndex
        let count = StrengthBoardPlanner.lane(allExercises, day: dayIndex, offloaded: false).count
        return Button {
            withAnimation { selectedDay = dayIndex }
        } label: {
            VStack(spacing: 2) {
                Text(Calendar.current.shortWeekdaySymbols[dayIndex])
                    .font(.caption.bold())
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : (isToday ? Color.blue.opacity(0.12) : Color.gray.opacity(0.08)))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strength.dayChip.\(dayIndex)")
        // Dragging a card onto a chip moves it to the end of that day's plan.
        // The board deliberately stays on the day the user is viewing — the
        // chip's count updating is the confirmation that the move landed.
        .dropDestination(for: StrengthExerciseDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            handleDrop(id: item.exerciseID, day: dayIndex, offloaded: false, target: nil)
            return true
        }
    }

    // MARK: - Board Mutations

    /// Adds a library entry to the end of the selected day's active plan,
    /// carrying the sets × reps plan drafted in the library sheet, and makes
    /// sure its lift exists with the entry's primary metric.
    private func addFromLibrary(_ entry: LibraryExercise, plan: StrengthPlanDraft) {
        let exercise = StrengthExercise(
            name: entry.name,
            libraryExerciseID: entry.id,
            muscleGroup: entry.muscleGroup,
            weekdayIndex: selectedDay,
            sortOrder: StrengthBoardPlanner.nextSortOrder(allExercises, day: selectedDay, offloaded: false),
            plannedSets: plan.plannedSets,
            plannedReps: plan.plannedReps
        )
        withAnimation {
            modelContext.insert(exercise)
            StrengthLiftRegistry.findOrCreate(for: exercise, metric: entry.primaryMetric, in: modelContext)
        }
    }

    /// Every movement group, built-in and the athlete's, by id.
    private var movementGroups: [String: MovementGroup] {
        StrengthSlotResolver.byID(MovementGroupCatalog.merged(
            builtIns: MovementGroupCatalog.bundled, user: userGroups.map(\.group)
        ))
    }

    /// Adds a movement group to the end of the selected day's active plan.
    /// Member lifts are created when first recorded.
    private func addGroup(_ group: MovementGroup, plan: StrengthPlanDraft) {
        let exercise = StrengthExercise(
            name: group.name,
            muscleGroup: group.muscleGroup,
            weekdayIndex: selectedDay,
            sortOrder: StrengthBoardPlanner.nextSortOrder(allExercises, day: selectedDay, offloaded: false),
            plannedSets: plan.plannedSets,
            plannedReps: plan.plannedReps,
            groupID: group.id
        )
        withAnimation { modelContext.insert(exercise) }
    }

    /// Resolves a dropped card ID and moves it via the board planner.
    private func handleDrop(id: UUID, day: Int, offloaded: Bool, target: StrengthExercise?) {
        guard let moving = allExercises.first(where: { $0.id == id }) else { return }
        withAnimation {
            StrengthBoardPlanner.move(moving, toDay: day, offloaded: offloaded, before: target, in: allExercises)
        }
    }

    /// Context-menu move: appends the exercise to the target day's active plan.
    /// Like a drag onto a day chip, this leaves the board on the current day
    /// rather than following the exercise.
    private func moveToDay(_ exercise: StrengthExercise, day: Int) {
        withAnimation {
            StrengthBoardPlanner.move(exercise, toDay: day, offloaded: false, before: nil, in: allExercises)
        }
    }
}

#Preview {
    NavigationStack { StrengthTrainingView() }
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}


/// A request to edit a card's group: its group, or a new one seeded from a
/// single-lift card ("Make This a Group").
struct SlotGroupEdit: Identifiable {
    let id = UUID()
    let slot: StrengthExercise
    let group: MovementGroup

    /// Builds the request from the card and the known groups.
    init(slot: StrengthExercise, groups: [String: MovementGroup]) {
        self.slot = slot
        if let groupID = slot.groupID, let existing = groups[groupID] {
            self.group = existing
        } else {
            let entry = MovementGroupCatalog.bundledLibrary.first { $0.id == slot.libraryExerciseID }
            self.group = MovementGroupDraft.seed(from: slot, entry: entry)
        }
    }
}
