//
//  StrengthExercise.swift
//  Train
//
//  A strength exercise on the weekly kanban board — a *slot* for a lift.
//  Unlike aerobic `Exercise`, it has NO date: it lives permanently in a
//  day-of-week lane (or that lane's "offloaded" section). Recorded history
//  belongs to the lift (`StrengthLift`, via `liftKey`), not the card, so the
//  same lift on two days shares one history and deleting a card keeps it.
//

import Foundation
import SwiftData

@Model
final class StrengthExercise {
    /// Stable identifier used for drag-and-drop transfer and list identity.
    var id: UUID = UUID()
    /// Display name, e.g. "Barbell Bench Press".
    var name: String = ""
    /// Identifier of the library entry this exercise was added from, or `nil`
    /// for an exercise with no library provenance. Lets us re-resolve library
    /// metadata (description, equipment) without denormalizing all of it.
    var libraryExerciseID: String? = nil
    /// Raw value of the primary muscle group. Stored as String because
    /// `MuscleGroup`'s custom tolerant `init(from:)` makes SwiftData treat
    /// the enum as a composite Codable attribute, which crashes its encoder
    /// on save. Access through `muscleGroup`, never this.
    private var muscleGroupRaw: String = MuscleGroup.other.rawValue
    /// The day-of-week lane this exercise lives in (Sunday=0 ... Saturday=6).
    var weekdayIndex: Int = 0
    /// Whether the exercise sits in the lane's lower "offloaded" section —
    /// kept in mind but dragged out of the active plan for the week.
    var isOffloaded: Bool = false
    /// Position within its lane section (active or offloaded). Lower = higher
    /// on the board. Order matters per swimlane.
    var sortOrder: Int = 0
    /// Optional user notes for the exercise.
    var notes: String = ""
    /// Planned number of sets, or `nil` when no plan is set. Plan-only data
    /// for the user's weekly set structure — never part of the recorded
    /// `StrengthWorkout` history.
    var plannedSets: Int? = nil
    /// Planned reps per set, or `nil` when no plan is set.
    var plannedReps: Int? = nil
    /// The movement group (#24) this card plans instead of a single lift,
    /// or `nil` for a single-lift card. A group card's `name` and
    /// `muscleGroup` mirror the group; the lift it records is the group's
    /// up-next member (`GroupRotation`), never `liftKey`.
    var groupID: String? = nil

    /// Primary muscle group, denormalized from the library for card display.
    /// Unknown stored raw values (e.g. synced from a newer app version) read
    /// as `.other`.
    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .other }
        set { muscleGroupRaw = newValue.rawValue }
    }

    /// The lift this card is a slot for: its history, metric and records
    /// live on the lift under this key, so they outlive the card.
    /// Meaningless for a group card — resolve its member instead.
    var liftKey: String {
        StrengthLiftKey.make(libraryID: libraryExerciseID, name: name)
    }

    /// Compact plan badge text, e.g. "3×8". `nil` unless both sets and reps
    /// are set.
    var plannedSummary: String? {
        guard let plannedSets, let plannedReps else { return nil }
        return "\(plannedSets)×\(plannedReps)"
    }

    /// Creates a strength exercise.
    /// - Parameters:
    ///   - name: Display name.
    ///   - libraryExerciseID: Library entry this was added from, if any.
    ///   - muscleGroup: Primary muscle group.
    ///   - weekdayIndex: Day-of-week lane (Sunday=0 ... Saturday=6).
    ///   - isOffloaded: Whether it starts in the offloaded section.
    ///   - sortOrder: Position within the lane section.
    ///   - notes: Optional notes.
    ///   - plannedSets: Planned number of sets, if any.
    ///   - plannedReps: Planned reps per set, if any.
    ///   - groupID: The movement group this card plans, if any.
    init(
        name: String,
        libraryExerciseID: String? = nil,
        muscleGroup: MuscleGroup = .other,
        weekdayIndex: Int = 0,
        isOffloaded: Bool = false,
        sortOrder: Int = 0,
        notes: String = "",
        plannedSets: Int? = nil,
        plannedReps: Int? = nil,
        groupID: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.libraryExerciseID = libraryExerciseID
        self.muscleGroup = muscleGroup
        self.weekdayIndex = weekdayIndex
        self.isOffloaded = isOffloaded
        self.sortOrder = sortOrder
        self.notes = notes
        self.plannedSets = plannedSets
        self.plannedReps = plannedReps
        self.groupID = groupID
    }

    /// Whether this card plans a movement group rather than one lift.
    var isGroup: Bool { groupID != nil }
}
