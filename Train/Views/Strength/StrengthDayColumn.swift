//
//  StrengthDayColumn.swift
//  Train
//
//  One day's kanban column: the active exercise plan on top and the
//  "offloaded" holding section below. Both sections accept card drops —
//  dropping on a card inserts before it, dropping on empty section space
//  appends at the end. Order within each section matters and is preserved.
//

import SwiftUI
import SwiftData

/// A single day's column in the strength kanban board.
struct StrengthDayColumn: View {
    /// Day-of-week for this column (Sunday=0 ... Saturday=6).
    let dayIndex: Int
    /// All strength exercises (the column filters its own lanes).
    let allExercises: [StrengthExercise]
    /// The latest record per lift key (see
    /// `StrengthLiftRegistry.latestByLiftKey`), for each card's summary.
    let latestRecords: [String: StrengthRecord]
    /// This week's latest record per card (see `StrengthWeek.recordsBySlot`),
    /// for each card's ✓.
    var weekRecords: [UUID: StrengthRecord] = [:]
    /// Each group card's member (#24, `GroupRotation.assignments`).
    var assignments: [UUID: GroupAssignment] = [:]
    /// Opens the group editor for a card.
    var onGroup: ((StrengthExercise) -> Void)? = nil
    /// Opens a card's history.
    var onHistory: ((StrengthExercise) -> Void)? = nil
    /// Duplicates a card onto another day (#18).
    var onDuplicate: ((StrengthExercise, Int) -> Void)? = nil
    /// Copies this day's active plan onto another day (#18).
    var onCopyDay: ((Int) -> Void)? = nil
    /// Called when the user taps a card to record a weight entry.
    let onRecord: (StrengthExercise) -> Void
    /// Called when the user taps the add button to open the exercise library.
    let onAddExercise: () -> Void
    /// Called to log the lane's active lifts in one sheet.
    let onLogDay: () -> Void
    /// The lane's "Done as planned" button (#26), or `nil` to hide it.
    var asPlanned: AsPlannedAction? = nil

    /// A one-tap "as planned" log for this lane.
    struct AsPlannedAction {
        /// Button title, e.g. "Done as planned" or "Done as planned · Tue".
        let title: String
        /// Logs every pending card at once.
        let log: () -> Void
        /// Opens the whole-day sheet pre-ticked instead.
        let logWithChanges: () -> Void
    }
    /// Called when a card is dropped: move `id` to this day's section
    /// (`offloaded`), inserting before `target` (nil = append at end).
    let onDrop: (_ id: UUID, _ offloaded: Bool, _ target: StrengthExercise?) -> Void
    /// Called when the user picks a context-menu destination day for a card.
    let onMoveToDay: (StrengthExercise, Int) -> Void
    /// Called when the user deletes a card.
    let onDelete: (StrengthExercise) -> Void

    /// Exercises in this day's active plan, in board order.
    private var activeExercises: [StrengthExercise] {
        StrengthBoardPlanner.lane(allExercises, day: dayIndex, offloaded: false)
    }

    /// Exercises in this day's offloaded section, in board order.
    private var offloadedExercises: [StrengthExercise] {
        StrengthBoardPlanner.lane(allExercises, day: dayIndex, offloaded: true)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                section(
                    title: "Plan",
                    systemImage: "list.bullet",
                    exercises: activeExercises,
                    offloaded: false,
                    emptyHint: "No exercises planned.\nTap + to add from the library."
                )
                section(
                    title: "Offloaded",
                    systemImage: "tray",
                    exercises: offloadedExercises,
                    offloaded: true,
                    emptyHint: "Drag exercises here to keep them\nhandy without planning them."
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("strengthDayColumn.\(dayIndex)")
    }

    /// The lane's one-tap "Done as planned" button; long-press for the
    /// whole-day sheet pre-ticked. Strength only — it never touches cardio.
    private func asPlannedButton(_ action: AsPlannedAction) -> some View {
        Button(action: action.log) {
            Label(action.title, systemImage: "dumbbell.fill")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.green)
        .contextMenu {
            Button(action: action.logWithChanges) {
                Label("Log with changes…", systemImage: "slider.horizontal.3")
            }
        }
        .accessibilityIdentifier("strengthDayColumn.logAsPlanned.\(dayIndex)")
    }

    /// Builds one droppable section (active plan or offloaded) of the column.
    private func section(
        title: String,
        systemImage: String,
        exercises: [StrengthExercise],
        offloaded: Bool,
        emptyHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !offloaded && !exercises.isEmpty, let onCopyDay {
                    Menu {
                        Section("Copy this day to") {
                            ForEach(0..<7, id: \.self) { day in
                                if day != dayIndex {
                                    Button(Calendar.current.weekdaySymbols[day]) { onCopyDay(day) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Copy day")
                    .accessibilityIdentifier("strengthDayColumn.copyDay.\(dayIndex)")
                }
                if !offloaded && !exercises.isEmpty {
                    Button(action: onLogDay) {
                        Image(systemName: "checklist")
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Log day")
                    .accessibilityIdentifier("strengthDayColumn.logDay.\(dayIndex)")
                }
                if !offloaded {
                    Button(action: onAddExercise) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("Add exercise")
                    .accessibilityIdentifier("strengthDayColumn.add.\(dayIndex)")
                }
            }
            if !offloaded, let asPlanned {
                asPlannedButton(asPlanned)
            }
            if exercises.isEmpty {
                Text(emptyHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(exercises) { exercise in
                    StrengthExerciseCard(
                        exercise: exercise,
                        latestRecord: latestRecords[assignments[exercise.id]?.member.liftKey ?? exercise.liftKey],
                        weekRecord: weekRecords[exercise.id],
                        assignment: assignments[exercise.id],
                        onGroup: onGroup.map { handler in { handler(exercise) } },
                        onHistory: onHistory.map { handler in { handler(exercise) } },
                        onDuplicate: onDuplicate.map { handler in { day in handler(exercise, day) } },
                        onRecord: { onRecord(exercise) },
                        onMoveToDay: { day in onMoveToDay(exercise, day) },
                        onToggleOffloaded: {
                            onDrop(exercise.id, !exercise.isOffloaded, nil)
                        },
                        onDelete: { onDelete(exercise) }
                    )
                    // Dropping on a card inserts the dragged card before it.
                    .dropDestination(for: StrengthExerciseDragItem.self) { items, _ in
                        guard let item = items.first, item.exerciseID != exercise.id else { return false }
                        onDrop(item.exerciseID, offloaded, exercise)
                        return true
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(offloaded ? Color.gray.opacity(0.08) : Color.blue.opacity(0.05))
        )
        .contentShape(Rectangle())
        // Dropping on the section background appends at the end of the lane.
        .dropDestination(for: StrengthExerciseDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            onDrop(item.exerciseID, offloaded, nil)
            return true
        }
    }
}

#Preview {
    StrengthDayColumn(
        dayIndex: 1,
        allExercises: [],
        latestRecords: [:],
        onRecord: { _ in },
        onAddExercise: {},
        onLogDay: {},
        onDrop: { _, _, _ in },
        onMoveToDay: { _, _ in },
        onDelete: { _ in }
    )
    .modelContainer(ModelContainerFactory.makePreviewContainer())
}
