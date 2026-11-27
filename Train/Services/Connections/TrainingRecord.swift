//
//  TrainingRecord.swift
//  Train
//
//  The canonical interchange model (#21): one recorded cardio workout or one
//  recorded strength session, independent of how it is stored or where it is
//  going. Every codec (CSV, Sheets rows, HealthKit, FIT) converts to and from
//  this type, and every import goes through `TrainingImporter`.
//
//  `externalID` is the dedupe anchor: the source's own ID when the record
//  came from outside (a HealthKit UUID, a Garmin activity ID), otherwise the
//  app's own UUID. It only ever stops the same activity being imported, or
//  offered for import, twice. Exports never merge by it.
//

import Foundation
import SwiftData

/// One recorded activity in the interchange format.
enum TrainingRecord: Equatable, Sendable {
    case cardio(Cardio)
    case strength(Strength)

    /// A recorded cardio workout. Distance is in miles, the app's internal
    /// unit.
    struct Cardio: Equatable, Sendable {
        /// Dedupe anchor; `nil` when the source had none (an old CSV).
        var externalID: String?
        /// Provenance, a `WorkoutSource` raw value.
        var source: String = WorkoutSource.manual.rawValue
        var date: Date
        var name: String
        var type: ExerciseType
        var durationSeconds: Int = 0
        var distanceMiles: Double = 0
        var notes: String = ""
        /// 1–5, `nil` when not recorded.
        var feeling: Int? = nil
        /// RPE 1–10, `nil` when not recorded.
        var perceivedExertion: Int? = nil
        var countsTowardTraining: Bool = true
        var isKeyWorkout: Bool = false
    }

    /// A recorded strength session for one lift. The value is in the
    /// metric's internal unit (lb, count, seconds, miles).
    struct Strength: Equatable, Sendable {
        /// Dedupe anchor; `nil` when the source had none.
        var externalID: String?
        var date: Date
        /// The lift's identity key (see `StrengthLiftKey`).
        var liftKey: String
        var liftName: String
        var muscleGroup: MuscleGroup = .other
        var metric: LiftMetric = .weight
        /// `nil` means "done" with no number.
        var value: Double? = nil
        /// Weight and reps only.
        var measurement: LiftMeasurement? = nil
        var isLight: Bool = false
        var notes: String = ""
        /// The lift's own training opt-out (#17).
        var countsTowardTraining: Bool = true
    }

    /// The dedupe anchor, whichever kind this is.
    var externalID: String? {
        switch self {
        case .cardio(let cardio): return cardio.externalID
        case .strength(let strength): return strength.externalID
        }
    }

    /// When the activity happened.
    var date: Date {
        switch self {
        case .cardio(let cardio): return cardio.date
        case .strength(let strength): return strength.date
        }
    }
}

// MARK: - App models → records

extension TrainingRecord.Cardio {
    /// Reads a recorded exercise. Recorded actuals win over planned targets.
    /// - Parameter exercise: The exercise to read.
    /// - Returns: `nil` for a planned exercise that was never recorded.
    init?(exercise: Exercise) {
        guard let workout = exercise.workout else { return nil }
        self.init(
            externalID: workout.externalID ?? exercise.id.uuidString,
            source: workout.source,
            date: exercise.date,
            name: exercise.name,
            type: exercise.type,
            durationSeconds: workout.durationSeconds,
            distanceMiles: workout.distanceMiles,
            notes: workout.notes,
            feeling: workout.feeling,
            perceivedExertion: workout.perceivedExertion,
            countsTowardTraining: exercise.countsTowardTraining,
            isKeyWorkout: exercise.isKeyWorkout
        )
    }

    /// A new completed exercise for this record, its planned targets
    /// mirroring the actuals, as every import has always created.
    /// - Parameter importBatchID: The import that created it, for Undo.
    func makeExercise(importBatchID: UUID? = nil) -> Exercise {
        let exercise = Exercise(
            name: name,
            type: type,
            durationSeconds: durationSeconds,
            distanceMiles: distanceMiles,
            notes: notes,
            date: date,
            countsTowardTraining: countsTowardTraining,
            isKeyWorkout: isKeyWorkout,
            workout: Workout(
                durationSeconds: durationSeconds,
                distanceMiles: distanceMiles,
                notes: notes,
                feeling: feeling,
                perceivedExertion: perceivedExertion,
                source: source,
                externalID: externalID
            )
        )
        exercise.importBatchID = importBatchID
        return exercise
    }
}

extension TrainingRecord.Strength {
    /// Reads a strength record with its lift's identity.
    /// - Parameters:
    ///   - record: The record to read.
    ///   - lift: Its lift, or `nil` when the lift row is missing (the key
    ///     then stands in for the name).
    init(record: StrengthRecord, lift: StrengthLift?) {
        self.init(
            externalID: record.externalID ?? record.id.uuidString,
            date: record.date,
            liftKey: record.liftKey,
            liftName: lift?.name ?? String(record.liftKey.trimmingPrefix(StrengthLiftKey.namePrefix)),
            muscleGroup: lift?.muscleGroup ?? .other,
            metric: record.metric,
            value: record.value,
            measurement: record.measurement,
            isLight: record.isLight,
            notes: record.notes,
            countsTowardTraining: lift?.countsTowardTraining ?? true
        )
    }
}

// MARK: - Snapshot

/// Everything an export writes, read once from the store: recorded cardio
/// and strength, oldest first, plus the athlete's unit preference.
struct TrainingSnapshot: Equatable, Sendable {
    var cardio: [TrainingRecord.Cardio]
    var strength: [TrainingRecord.Strength]
    var useMetricUnits: Bool

    /// Reads the snapshot from a context. Pure read; never saves.
    /// - Parameter context: The context to fetch from.
    static func load(from context: ModelContext) throws -> TrainingSnapshot {
        let useMetric = (try? context.fetch(FetchDescriptor<AppConfiguration>()).first?.useMetricUnits) ?? false
        let exercises = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.date)]))
        let records = try context.fetch(FetchDescriptor<StrengthRecord>(sortBy: [SortDescriptor(\.date)]))
        let lifts = try context.fetch(FetchDescriptor<StrengthLift>())
        return TrainingSnapshot(
            cardio: exercises.compactMap(TrainingRecord.Cardio.init(exercise:)),
            strength: records.map {
                TrainingRecord.Strength(record: $0, lift: StrengthLiftRegistry.lift(forKey: $0.liftKey, in: lifts))
            },
            useMetricUnits: useMetric
        )
    }
}
