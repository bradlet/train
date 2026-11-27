//
//  TrainingImporter.swift
//  Train
//
//  The one write path for imports (#21). Every source (CSV, Apple Health,
//  later Garmin) hands it `TrainingRecord`s; it skips anything already in the
//  app by `externalID`, inserts the rest stamped with a new `ImportBatch`,
//  and can undo that batch.
//

import Foundation
import SwiftData

/// Imports interchange records into SwiftData, with dedupe and undo.
enum TrainingImporter {

    /// What an import did.
    struct Outcome: Equatable {
        /// The log entry, or `nil` when nothing new was added.
        var batchID: UUID?
        var cardioAdded: Int = 0
        var strengthAdded: Int = 0
        /// Records skipped as already in the app (or repeated in the input).
        var duplicates: Int = 0

        /// Records added in total.
        var added: Int { cardioAdded + strengthAdded }
    }

    /// Every dedupe anchor already in the store: each recorded exercise's
    /// own ID and external ID, and each strength record's.
    /// - Parameter context: The context to read.
    static func knownIDs(in context: ModelContext) -> Set<String> {
        var ids = Set<String>()
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] {
            ids.insert(exercise.id.uuidString)
            if let external = exercise.workout?.externalID { ids.insert(external) }
        }
        for record in (try? context.fetch(FetchDescriptor<StrengthRecord>())) ?? [] {
            ids.insert(record.id.uuidString)
            if let external = record.externalID { ids.insert(external) }
        }
        return ids
    }

    /// Whether a record is new: it has no anchor, or its anchor is unknown.
    /// - Parameters:
    ///   - record: The candidate.
    ///   - known: Anchors already present.
    static func isNew(_ record: TrainingRecord, known: Set<String>) -> Bool {
        guard let id = record.externalID else { return true }
        return !known.contains(id)
    }

    /// Imports records, skipping any already present, and logs the batch.
    /// A new lift is created for an unknown lift key; an existing lift keeps
    /// its own metric and settings.
    /// - Parameters:
    ///   - records: The records to import.
    ///   - source: Where they came from.
    ///   - context: The context to write to. Saved on success.
    ///   - now: The batch's timestamp.
    /// - Returns: What was added; no batch is logged when nothing was.
    @discardableResult
    static func importRecords(
        _ records: [TrainingRecord],
        from source: ConnectionID,
        into context: ModelContext,
        now: Date = Date()
    ) throws -> Outcome {
        var known = knownIDs(in: context)
        var fresh: [TrainingRecord] = []
        for record in records where isNew(record, known: known) {
            fresh.append(record)
            if let id = record.externalID { known.insert(id) }
        }
        var outcome = Outcome(duplicates: records.count - fresh.count)
        guard !fresh.isEmpty else { return outcome }

        let batch = ImportBatch(source: source, date: now)
        context.insert(batch)
        for record in fresh {
            switch record {
            case .cardio(let cardio):
                context.insert(cardio.makeExercise(importBatchID: batch.id))
                outcome.cardioAdded += 1
            case .strength(let strength):
                insert(strength, batchID: batch.id, in: context)
                outcome.strengthAdded += 1
            }
        }
        batch.cardioCount = outcome.cardioAdded
        batch.strengthCount = outcome.strengthAdded
        batch.duplicateCount = outcome.duplicates
        try context.save()
        outcome.batchID = batch.id
        return outcome
    }

    /// Inserts one strength session, resolving or creating its lift.
    private static func insert(_ strength: TrainingRecord.Strength, batchID: UUID, in context: ModelContext) {
        let key = strength.liftKey
        let existing = (try? context.fetch(FetchDescriptor<StrengthLift>(predicate: #Predicate { $0.liftKey == key }))) ?? []
        if existing.isEmpty {
            let isLibrary = !key.hasPrefix(StrengthLiftKey.namePrefix)
            let lift = StrengthLiftRegistry.findOrCreate(
                for: LiftTarget(
                    liftKey: key,
                    name: strength.liftName,
                    libraryExerciseID: isLibrary ? key : nil,
                    muscleGroup: strength.muscleGroup,
                    defaultMetric: strength.metric
                ),
                metric: strength.metric,
                in: context
            )
            lift.countsTowardTraining = strength.countsTowardTraining
            if strength.value != nil, strength.metric.usesMeasurement {
                lift.defaultMeasurement = strength.measurement
            }
        }
        let record = StrengthRecord(
            liftKey: key,
            date: strength.date,
            value: strength.value,
            metric: strength.metric,
            measurement: strength.measurement,
            notes: strength.notes
        )
        record.isLight = strength.isLight
        record.externalID = strength.externalID
        record.importBatchID = batchID
        context.insert(record)
    }

    // MARK: - Log and undo

    /// The import log, newest first.
    /// - Parameter context: The context to read.
    static func batches(in context: ModelContext) -> [ImportBatch] {
        (try? context.fetch(FetchDescriptor<ImportBatch>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    /// Removes everything an import added, and its log entry. A lift the
    /// import created is removed too when nothing else uses it (no records
    /// left, no board card).
    /// - Parameters:
    ///   - batch: The import to undo.
    ///   - context: The context to write to. Saved on success.
    /// - Returns: How many workouts and sessions were removed.
    @discardableResult
    static func undo(_ batch: ImportBatch, in context: ModelContext) throws -> (cardio: Int, strength: Int) {
        let batchID: UUID? = batch.id
        let exercises = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.importBatchID == batchID }))
        let records = try context.fetch(FetchDescriptor<StrengthRecord>(predicate: #Predicate { $0.importBatchID == batchID }))
        let liftKeys = Set(records.map(\.liftKey))
        exercises.forEach(context.delete)
        records.forEach(context.delete)

        let since = batch.date
        // `StrengthExercise.liftKey` is computed, so cards are matched in memory.
        let cardKeys = Set(try context.fetch(FetchDescriptor<StrengthExercise>()).map(\.liftKey))
        for key in liftKeys where !cardKeys.contains(key) {
            let lifts = try context.fetch(FetchDescriptor<StrengthLift>(predicate: #Predicate { $0.liftKey == key }))
            let remaining = try context.fetchCount(FetchDescriptor<StrengthRecord>(predicate: #Predicate { $0.liftKey == key }))
            guard remaining == 0 else { continue }
            lifts.filter { $0.createdAt >= since }.forEach(context.delete)
        }
        context.delete(batch)
        try context.save()
        return (exercises.count, records.count)
    }
}
