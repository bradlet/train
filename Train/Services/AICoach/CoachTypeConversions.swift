//
//  CoachTypeConversions.swift
//  Train
//
//  Extensions to convert the app's SwiftData `Exercise` model (and its nested
//  `Workout` value) into AICoachCore's plain types for prompt building.
//

import Foundation
import AICoachCore

extension CoachExerciseType {

    /// Creates a coaching exercise type from the app's UI-aware `ExerciseType`.
    init(from appType: ExerciseType) {
        // Raw values are identical between the two enums by design.
        self = CoachExerciseType(rawValue: appType.rawValue)!
    }
}

extension ExerciseType {

    /// Creates the app's UI-aware exercise type from a coaching type.
    ///
    /// The reverse of `CoachExerciseType(from:)`. Raw values are identical by
    /// design, so an unknown value means the two enums have drifted apart —
    /// fall back to `.other` rather than trapping on data that arrived from a
    /// language model.
    init(from coachType: CoachExerciseType) {
        self = ExerciseType(rawValue: coachType.rawValue) ?? .other
    }
}

extension CoachWorkout {

    /// Creates a coaching workout from a completed `Exercise` (one whose
    /// `workout` is non-nil). Date and type come from the exercise; the
    /// metrics and ratings come from the recorded `workout`. Falls back to the
    /// planned metrics if `workout` is unexpectedly nil.
    init(from exercise: Exercise) {
        self.init(
            date: exercise.date,
            type: CoachExerciseType(from: exercise.type),
            distanceMiles: exercise.workout?.distanceMiles ?? exercise.distanceMiles,
            durationSeconds: exercise.workout?.durationSeconds ?? exercise.durationSeconds,
            // `workout?.feeling` is Int?? — flatten so an absent workout and
            // an unrated one both arrive as nil.
            feeling: exercise.workout?.feeling ?? nil,
            perceivedExertion: exercise.workout?.perceivedExertion ?? nil,
            notes: exercise.workout?.notes ?? ""
        )
    }
}

extension CoachExercise {

    /// Creates a coaching exercise from the app's SwiftData `Exercise` model,
    /// reading its planned (target) metrics.
    init(from exercise: Exercise) {
        self.init(
            scheduledDate: exercise.date,
            type: CoachExerciseType(from: exercise.type),
            distanceMiles: exercise.distanceMiles,
            durationSeconds: exercise.durationSeconds
        )
    }
}

extension CoachMuscleGroup {

    /// Creates a coaching muscle group from the app's UI-aware `MuscleGroup`.
    /// Raw values are identical between the two enums by design; an unknown
    /// value reads as `.other`, matching `MuscleGroup`'s tolerant decode.
    init(from appGroup: MuscleGroup) {
        self = CoachMuscleGroup(rawValue: appGroup.rawValue) ?? .other
    }
}

extension MuscleGroup {

    /// Creates the app's UI-aware muscle group from a coaching type.
    ///
    /// The reverse of `CoachMuscleGroup(from:)`, with the same `.other`
    /// fallback for values that arrive from a language model.
    init(from coachGroup: CoachMuscleGroup) {
        self = MuscleGroup(rawValue: coachGroup.rawValue) ?? .other
    }
}

extension CoachStrengthWorkout {

    /// Creates a coaching snapshot from a recorded strength session, or
    /// `nil` for one the weight-only coach snapshot can't carry. The coach
    /// is being reworked separately (out of scope for #13), so for now only
    /// weight records with a value are passed through; reps, time, distance
    /// and value-less "done" records are left out. Empty notes arrive as
    /// `nil` so they stay out of prompt output.
    init?(from record: StrengthRecord) {
        guard record.metric == .weight, let pounds = record.value else { return nil }
        self.init(
            date: record.date,
            weightPounds: pounds,
            recordingType: (record.measurement ?? .max).displayName,
            notes: record.notes.isEmpty ? nil : record.notes
        )
    }
}

extension CoachStrengthExercise {

    /// Creates a coaching snapshot from a board exercise and its lift's
    /// recorded history (shared by every card for the same lift), sorted
    /// oldest first. Empty notes arrive as `nil`.
    /// - Parameters:
    ///   - exercise: The board card.
    ///   - records: All strength records; filtered to the card's lift.
    init(from exercise: StrengthExercise, records: [StrengthRecord]) {
        self.init(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup.rawValue,
            weekdayIndex: exercise.weekdayIndex,
            isOffloaded: exercise.isOffloaded,
            notes: exercise.notes.isEmpty ? nil : exercise.notes,
            plannedSets: exercise.plannedSets,
            plannedReps: exercise.plannedReps,
            workouts: StrengthLiftRegistry.records(forKey: exercise.liftKey, in: records)
                .compactMap { CoachStrengthWorkout(from: $0) }
        )
    }

    /// Converts board exercises into coach snapshots, in board order (day,
    /// then section, then position).
    /// - Parameters:
    ///   - exercises: The board cards.
    ///   - records: All strength records.
    static func snapshots(
        from exercises: [StrengthExercise],
        records: [StrengthRecord] = []
    ) -> [CoachStrengthExercise] {
        exercises
            .sorted {
                ($0.weekdayIndex, $0.isOffloaded ? 1 : 0, $0.sortOrder)
                    < ($1.weekdayIndex, $1.isOffloaded ? 1 : 0, $1.sortOrder)
            }
            .map { CoachStrengthExercise(from: $0, records: records) }
    }
}
