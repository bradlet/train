//
//  StrengthLiftRegistry.swift
//  Train
//
//  The one place that resolves lifts and their records from keys. Views pass
//  in what their `@Query`s returned; only `findOrCreate` touches a context.
//  Pure and unit-tested, like `StrengthBoardPlanner`.
//

import Foundation
import SwiftData

/// Lookups between board slots, lifts and records.
enum StrengthLiftRegistry {

    /// The lift for a key, resolving CloudKit duplicates to the oldest.
    /// - Parameters:
    ///   - key: The lift key.
    ///   - lifts: Candidate lifts.
    static func lift(forKey key: String, in lifts: [StrengthLift]) -> StrengthLift? {
        lifts.filter { $0.liftKey == key }.min { $0.createdAt < $1.createdAt }
    }

    /// The metric to record a slot in: its lift's primary metric, or weight
    /// when no lift exists yet.
    /// - Parameters:
    ///   - slot: The board card.
    ///   - lifts: Candidate lifts.
    static func metric(for slot: StrengthExercise, in lifts: [StrengthLift]) -> LiftMetric {
        lift(forKey: slot.liftKey, in: lifts)?.primaryMetric ?? .weight
    }

    /// The metric to record a slot in, fetched from a context — includes
    /// lifts inserted but not yet saved, so a card added a moment ago
    /// resolves to the metric its lift was just created with.
    /// - Parameters:
    ///   - slot: The board card.
    ///   - context: The context to fetch lifts from.
    static func metric(for slot: StrengthExercise, in context: ModelContext) -> LiftMetric {
        let key = slot.liftKey
        let descriptor = FetchDescriptor<StrengthLift>(predicate: #Predicate { $0.liftKey == key })
        return lift(forKey: key, in: (try? context.fetch(descriptor)) ?? [])?.primaryMetric ?? .weight
    }

    /// Returns the slot's lift, inserting one when none exists. An existing
    /// lift keeps its metric — `metric` only seeds a new one.
    /// - Parameters:
    ///   - slot: The board card whose lift to resolve.
    ///   - metric: Primary metric for a newly created lift.
    ///   - context: The context to search and insert into.
    @discardableResult
    static func findOrCreate(
        for slot: StrengthExercise,
        metric: LiftMetric,
        in context: ModelContext
    ) -> StrengthLift {
        findOrCreate(for: LiftTarget(slot: slot), metric: metric, in: context)
    }

    /// Returns a target's lift — a card's own or a group member (#24) —
    /// inserting one when none exists. An existing lift keeps its metric.
    /// - Parameters:
    ///   - target: The lift to resolve.
    ///   - metric: Primary metric for a newly created lift.
    ///   - context: The context to search and insert into.
    @discardableResult
    static func findOrCreate(
        for target: LiftTarget,
        metric: LiftMetric,
        in context: ModelContext
    ) -> StrengthLift {
        let key = target.liftKey
        let descriptor = FetchDescriptor<StrengthLift>(predicate: #Predicate { $0.liftKey == key })
        if let existing = lift(forKey: key, in: (try? context.fetch(descriptor)) ?? []) {
            return existing
        }
        let lift = StrengthLift(
            liftKey: key,
            name: target.name,
            libraryExerciseID: target.libraryExerciseID,
            muscleGroup: target.muscleGroup,
            primaryMetric: metric
        )
        context.insert(lift)
        return lift
    }

    /// Remembers a just-saved record's measurement as its lift's default,
    /// so the next session prefills it. Only a weight or reps record with a
    /// value counts: a "done" record says nothing about the measurement.
    /// - Parameters:
    ///   - record: The record that was saved.
    ///   - context: The context to fetch the lift from.
    static func rememberDefaults(after record: StrengthRecord, in context: ModelContext) {
        guard record.value != nil, record.metric.usesMeasurement, let measurement = record.measurement else { return }
        let key = record.liftKey
        let descriptor = FetchDescriptor<StrengthLift>(predicate: #Predicate { $0.liftKey == key })
        lift(forKey: key, in: (try? context.fetch(descriptor)) ?? [])?.defaultMeasurement = measurement
    }

    /// A lift's records, oldest first.
    /// - Parameters:
    ///   - key: The lift key.
    ///   - records: Candidate records.
    static func records(forKey key: String, in records: [StrengthRecord]) -> [StrengthRecord] {
        records.filter { $0.liftKey == key }.sorted { $0.date < $1.date }
    }

    /// A lift's records fetched from a context — including inserted but
    /// unsaved ones — oldest first. Used to compare a new record against the
    /// lift's history before it is inserted.
    /// - Parameters:
    ///   - key: The lift key.
    ///   - context: The context to fetch from.
    static func records(forKey key: String, in context: ModelContext) -> [StrengthRecord] {
        let descriptor = FetchDescriptor<StrengthRecord>(
            predicate: #Predicate { $0.liftKey == key },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The most recently dated record per lift key, for card display.
    /// - Parameter records: All records.
    static func latestByLiftKey(_ records: [StrengthRecord]) -> [String: StrengthRecord] {
        var latest: [String: StrengthRecord] = [:]
        for record in records {
            if let current = latest[record.liftKey], current.date >= record.date { continue }
            latest[record.liftKey] = record
        }
        return latest
    }
}
