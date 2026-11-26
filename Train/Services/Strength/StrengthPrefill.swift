//
//  StrengthPrefill.swift
//  Train
//
//  What a new strength record starts as, so recording is a nudge rather than
//  typing: the lift's usual measurement and the last value logged for it.
//  Pure and unit-tested; `resolve(for:in:)` is the one context-reading entry.
//

import Foundation
import SwiftData

/// The starting measurement and value for a new record of a lift.
struct StrengthPrefill: Equatable {
    /// The measurement to start on (weight and reps only; ignored otherwise).
    var measurement: LiftMeasurement
    /// The value to start from, in the metric's internal unit, or `nil` for
    /// a blank field.
    var value: Double?

    /// Nothing to go on: the starting measurement and a blank value.
    static let empty = StrengthPrefill(measurement: .starting, value: nil)

    /// Builds the prefill from a lift and its history.
    ///
    /// - Measurement: the lift's remembered default, else the latest
    ///   record's measurement, else `LiftMeasurement.starting` (Average).
    /// - Value: the most recent valued record in this metric *with that
    ///   measurement*, else the most recent valued record in this metric,
    ///   else blank. Records in another metric never prefill.
    /// - Parameters:
    ///   - metric: The metric being recorded.
    ///   - lift: The lift, if it exists yet.
    ///   - records: The lift's records, in any order.
    static func make(metric: LiftMetric, lift: StrengthLift?, records: [StrengthRecord]) -> StrengthPrefill {
        let newestFirst = records.sorted { $0.date > $1.date }
        let measurement = lift?.defaultMeasurement
            ?? newestFirst.first(where: { $0.measurement != nil })?.measurement
            ?? .starting
        let valued = newestFirst.filter { $0.metric == metric && $0.value != nil }
        let match = metric.usesMeasurement
            ? valued.first(where: { $0.measurement == measurement }) ?? valued.first
            : valued.first
        return StrengthPrefill(measurement: measurement, value: match?.value)
    }

    /// Resolves a card's metric and prefill from a context — includes lifts
    /// and records inserted but not yet saved.
    /// - Parameters:
    ///   - slot: The board card being recorded from.
    ///   - context: The context to fetch from.
    /// - Returns: The lift's metric and the prefill for a new record.
    static func resolve(for slot: StrengthExercise, in context: ModelContext) -> (metric: LiftMetric, prefill: StrengthPrefill) {
        resolve(for: LiftTarget(slot: slot), in: context)
    }

    /// Resolves a target lift's metric and prefill from a context. A lift
    /// that doesn't exist yet uses the target's default metric (a group
    /// member's library metric).
    /// - Parameters:
    ///   - target: The lift being recorded.
    ///   - context: The context to fetch from.
    static func resolve(for target: LiftTarget, in context: ModelContext) -> (metric: LiftMetric, prefill: StrengthPrefill) {
        let key = target.liftKey
        let lifts = (try? context.fetch(FetchDescriptor<StrengthLift>(predicate: #Predicate { $0.liftKey == key }))) ?? []
        let records = (try? context.fetch(FetchDescriptor<StrengthRecord>(predicate: #Predicate { $0.liftKey == key }))) ?? []
        let lift = StrengthLiftRegistry.lift(forKey: key, in: lifts)
        let metric = lift?.primaryMetric ?? target.defaultMetric
        return (metric, make(metric: metric, lift: lift, records: records))
    }
}
