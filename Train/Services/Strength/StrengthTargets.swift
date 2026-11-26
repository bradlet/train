//
//  StrengthTargets.swift
//  Train
//
//  Steady-mode plans (#20): an optional target per card, gentle nudges, a
//  changelog and a one-off light week. Nudges are suggestions only — the
//  target changes when the athlete taps one. Defaults (decided in
//  TRAINING_PLANS §9):
//
//  - ↑ after the target is met 2 sessions in a row: +5 lb upper / +10 lb
//    lower (2.5 / 5 kg), +1 rep, +15 s, or the distance stepper's increment.
//  - A stall after 3 misses in a row offers one step down.
//  - "Not yet" snoozes a nudge for 2 weeks.
//  - A light week shows every target ×0.9, rounded down to the stepper
//    increment, and reverts on its own when the week rolls over.
//
//  Only sessions since the target was last set count, so a new target never
//  nudges off old history. Pure and unit-tested; `StrengthTargetEditor` is
//  the one write path.
//

import Foundation
import SwiftData
import SwiftUI

/// A suggested target change.
enum TargetNudge: Equatable {
    /// Met twice in a row: try this next.
    case up(Double)
    /// Missed three times in a row: drop to this (or take a light week).
    case stall(Double)

    /// The suggested target.
    var value: Double {
        switch self {
        case .up(let value), .stall(let value): return value
        }
    }
}

/// What a card shows about its target.
struct CardTarget: Equatable {
    /// The target this week (scaled when light), in internal units.
    let value: Double
    /// The lift's metric.
    let metric: LiftMetric
    /// Whether this week is light.
    let isLight: Bool
    /// A nudge to offer, if any (never in a light week).
    let nudge: TargetNudge?
}

/// Pure target rules.
enum StrengthTargets {

    /// Met sessions in a row before an ↑ nudge.
    static let sessionsToNudgeUp = 2
    /// Missed sessions in a row before a stall nudge.
    static let missesToStall = 3
    /// How long "Not yet" snoozes a nudge.
    static let snoozeDays = 14
    /// Light-week scale.
    static let lightScale = 0.9

    /// One nudge step in the metric's internal unit.
    /// - Parameters:
    ///   - metric: The lift's metric.
    ///   - lowerBody: Whether the lift loads the legs (bigger weight jumps).
    ///   - useMetricUnits: Whether the athlete uses kg.
    static func step(metric: LiftMetric, lowerBody: Bool, useMetricUnits: Bool) -> Double {
        switch metric {
        case .weight:
            let display = useMetricUnits ? (lowerBody ? 5.0 : 2.5) : (lowerBody ? 10.0 : 5.0)
            return metric.storedValue(fromDisplay: display, metric: useMetricUnits)
        case .reps, .time, .distance:
            return metric.storedValue(fromDisplay: metric.stepIncrement(metric: useMetricUnits), metric: useMetricUnits)
        }
    }

    /// The nudge for a target, if any.
    /// - Parameters:
    ///   - target: The current target (internal units).
    ///   - records: The lift's records in the target's metric and
    ///     measurement, any order; only valued ones since `since` count.
    ///   - since: When the target was last set (`nil` = all history).
    ///   - step: One step (internal units).
    ///   - snoozedUntil: A "Not yet" snooze.
    ///   - now: The current moment.
    static func nudge(
        target: Double,
        records: [StrengthRecord],
        since: Date?,
        step: Double,
        snoozedUntil: Date?,
        now: Date
    ) -> TargetNudge? {
        if let snoozedUntil, snoozedUntil > now { return nil }
        var dated: [(date: Date, value: Double)] = []
        for record in records where !record.isLight {
            guard let value = record.value else { continue }
            if let since, record.date < since { continue }
            dated.append((record.date, value))
        }
        let recent = dated.sorted { $0.date > $1.date }.map(\.value)
        if recent.count >= sessionsToNudgeUp, recent.prefix(sessionsToNudgeUp).allSatisfy({ $0 >= target }) {
            return .up(target + step)
        }
        if recent.count >= missesToStall, recent.prefix(missesToStall).allSatisfy({ $0 < target }) {
            return .stall(max(target - step, step))
        }
        return nil
    }

    /// A light-week target: ×0.9, rounded down to the stepper increment in
    /// display units, never below one increment.
    static func lightTarget(_ target: Double, metric: LiftMetric, useMetricUnits: Bool) -> Double {
        let display = metric.displayValue(fromStored: target, metric: useMetricUnits)
        let increment = metric.stepIncrement(metric: useMetricUnits)
        let scaled = max((display * lightScale / increment).rounded(.down) * increment, increment)
        return metric.storedValue(fromDisplay: scaled, metric: useMetricUnits)
    }

    /// Whether a light week is on: it started at the current week's start.
    static func isLightWeek(start: Date?, now: Date, firstWeekday: Int) -> Bool {
        guard let start else { return false }
        return start.startOfWeek(firstWeekday: firstWeekday) == now.startOfWeek(firstWeekday: firstWeekday)
    }

    /// When a card's target was last set, from the changelog.
    static func lastSet(_ changes: [StrengthTargetChange], slotID: UUID) -> Date? {
        changes.filter { $0.slotID == slotID }.map(\.date).max()
    }

    /// The target step line for a lift's chart: each change in `metric`,
    /// oldest first (a `nil` value ends the line).
    static func history(_ changes: [StrengthTargetChange], liftKey: String, metric: LiftMetric) -> [(date: Date, value: Double?)] {
        changes.filter { $0.liftKey == liftKey && $0.metric == metric }
            .sorted { $0.date < $1.date }
            .map { ($0.date, $0.value) }
    }

    /// What a card shows: its (possibly light) target and any nudge.
    /// - Parameters:
    ///   - card: The card (group cards carry no target).
    ///   - lift: The card's lift, for its metric and measurement.
    ///   - records: The lift's records.
    ///   - changes: The target changelog.
    ///   - lowerBody: Whether the lift loads the legs.
    ///   - isLightWeek: Whether this week is light.
    ///   - useMetricUnits: Whether the athlete uses kg.
    ///   - now: The current moment.
    static func cardTarget(
        _ card: StrengthExercise,
        lift: StrengthLift?,
        records: [StrengthRecord],
        changes: [StrengthTargetChange],
        lowerBody: Bool,
        isLightWeek: Bool,
        useMetricUnits: Bool,
        now: Date
    ) -> CardTarget? {
        guard let target = card.targetValue, !card.isGroup else { return nil }
        let metric = lift?.primaryMetric ?? .weight
        if isLightWeek {
            return CardTarget(value: lightTarget(target, metric: metric, useMetricUnits: useMetricUnits),
                              metric: metric, isLight: true, nudge: nil)
        }
        let measurement = lift?.defaultMeasurement ?? .starting
        let comparable = records.filter {
            $0.liftKey == card.liftKey && $0.metric == metric
                && (!metric.usesMeasurement || $0.measurement == measurement)
        }
        let nudge = nudge(
            target: target,
            records: comparable,
            since: lastSet(changes, slotID: card.id),
            step: step(metric: metric, lowerBody: lowerBody, useMetricUnits: useMetricUnits),
            snoozedUntil: card.nudgeSnoozedUntil,
            now: now
        )
        return CardTarget(value: target, metric: metric, isLight: false, nudge: nudge)
    }
}

// MARK: - This week's target

extension StrengthTargets {
    /// A card's target as recorded this week: its target, scaled when
    /// light; `nil` for group cards and trend-only lifts.
    static func weekTarget(for card: StrengthExercise, metric: LiftMetric, isLightWeek: Bool, useMetricUnits: Bool) -> Double? {
        guard let target = card.targetValue, !card.isGroup else { return nil }
        return isLightWeek ? lightTarget(target, metric: metric, useMetricUnits: useMetricUnits) : target
    }
}

// MARK: - Editing

/// The one write path for targets: sets the card's target and logs it.
enum StrengthTargetEditor {

    /// Sets (or clears) a card's target, logging the change when it differs
    /// and clearing any snooze.
    /// - Parameters:
    ///   - value: The new target (internal units), or `nil` to clear.
    ///   - card: The card.
    ///   - metric: The lift's metric.
    ///   - context: The context to log into.
    ///   - now: When it changed.
    static func setTarget(_ value: Double?, on card: StrengthExercise, metric: LiftMetric, in context: ModelContext, now: Date = Date()) {
        guard card.targetValue != value else { return }
        card.targetValue = value
        card.nudgeSnoozedUntil = nil
        context.insert(StrengthTargetChange(liftKey: card.liftKey, slotID: card.id, date: now, value: value, metric: metric))
    }

    /// "Not yet": hides the card's nudge for two weeks.
    static func snooze(_ card: StrengthExercise, now: Date = Date()) {
        card.nudgeSnoozedUntil = Calendar.current.date(byAdding: .day, value: StrengthTargets.snoozeDays, to: now)
    }
}

// MARK: - Environment

private struct LightWeekKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether this week is a light week (#20), from `AppConfiguration`.
    var isLightWeek: Bool {
        get { self[LightWeekKey.self] }
        set { self[LightWeekKey.self] = newValue }
    }
}
