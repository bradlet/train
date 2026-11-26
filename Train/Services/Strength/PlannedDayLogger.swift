//
//  PlannedDayLogger.swift
//  Train
//
//  "Log lifts as planned" (#26): record a whole lane in one tap, strength
//  only. Every active card not yet recorded that day gets one record, built
//  exactly as the whole-day sheet would prefill it (`StrengthPrefill`: the
//  lift's default measurement and last value, else "done"). The rules are
//  pure and unit-tested; `log` and `undo` are the context entry points.
//
//  A group card logs its up-next member (#24, via `StrengthSlotResolver`).
//  Plan targets (TRAINING_PLANS) will feed the value once they exist.
//

import Foundation
import SwiftData

/// What one "as planned" tap wrote, so it can be undone or adjusted.
struct PlannedDayLogResult: Identifiable, Equatable {
    let id = UUID()
    /// The records inserted, by id — undo removes exactly these.
    let recordIDs: [UUID]
    /// The cards that were logged, in board order.
    let slotIDs: [UUID]
    /// The day the records are dated.
    let date: Date
    /// Names of lifts whose record is a new best (#15).
    let newBests: [String]

    /// How many lifts were logged.
    var count: Int { recordIDs.count }

    /// Toast text, e.g. "Logged 4 lifts" or "Logged 1 lift".
    var message: String { count == 1 ? "Logged 1 lift" : "Logged \(count) lifts" }
}

/// One-tap "as planned" logging for a strength lane.
enum PlannedDayLogger {

    /// The cards one tap would log: active cards in board order, minus any
    /// already recorded from that card on `date`.
    /// - Parameters:
    ///   - lane: The lane's cards (any order; offloaded ones are skipped).
    ///   - date: The day being logged.
    ///   - records: All strength records.
    static func pending(_ lane: [StrengthExercise], on date: Date, records: [StrengthRecord]) -> [StrengthExercise] {
        let calendar = Calendar.current
        let recordedSlots = Set(records.compactMap { record in
            calendar.isDate(record.date, inSameDayAs: date) ? record.slotID : nil
        })
        return lane
            .filter { !$0.isOffloaded && !recordedSlots.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// One record per card, prefilled from its lift's history. A card with
    /// no lift or no history records "done" — bodyweight and new lifts count.
    /// - Parameters:
    ///   - slots: The cards to log, in order.
    ///   - targets: The lift each card records (group cards' up-next
    ///     members); a card missing here records its own lift.
    ///   - date: The day the records are dated.
    ///   - lifts: Candidate lifts.
    ///   - records: All strength records.
    static func records(
        for slots: [StrengthExercise],
        targets: [UUID: LiftTarget] = [:],
        on date: Date,
        lifts: [StrengthLift],
        records: [StrengthRecord],
        isLightWeek: Bool = false,
        useMetricUnits: Bool = false
    ) -> [StrengthRecord] {
        slots.map { slot in
            let target = targets[slot.id] ?? LiftTarget(slot: slot)
            let lift = StrengthLiftRegistry.lift(forKey: target.liftKey, in: lifts)
            let metric = lift?.primaryMetric ?? target.defaultMetric
            let history = records.filter { $0.liftKey == target.liftKey }
            // A card's target is the plan (#20); it wins over the last value.
            let goal = target.liftKey == slot.liftKey
                ? StrengthTargets.weekTarget(for: slot, metric: metric, isLightWeek: isLightWeek, useMetricUnits: useMetricUnits)
                : nil
            let prefill = StrengthPrefill.make(metric: metric, lift: lift, records: history, target: goal)
            let made = StrengthRecord(
                liftKey: target.liftKey,
                slotID: slot.id,
                date: date,
                value: prefill.value,
                metric: metric,
                measurement: prefill.value == nil ? nil : prefill.measurement
            )
            made.isLight = isLightWeek
            return made
        }
    }

    /// The date a board lane logs as planned in the current week: now for
    /// today's lane, the lane's day for an earlier day (a backfill), and
    /// `nil` for a day still to come — the button is hidden then.
    /// - Parameters:
    ///   - weekdayIndex: The lane (Sunday=0 ... Saturday=6).
    ///   - now: The current moment.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func logDate(forLane weekdayIndex: Int, now: Date, firstWeekday: Int) -> Date? {
        let laneDate = StrengthWeek.date(ofLane: weekdayIndex, now: now, firstWeekday: firstWeekday)
        if Calendar.current.isDate(laneDate, inSameDayAs: now) { return now }
        return laneDate < now ? laneDate : nil
    }

    /// Logs the lane's pending cards: makes sure each lift exists, inserts
    /// the records, remembers default measurements, and notes new bests.
    /// - Parameters:
    ///   - lane: The lane's cards.
    ///   - date: The day the records are dated.
    ///   - context: The context to read from and insert into.
    ///   - firstWeekday: The week start, for group rotation.
    /// - Returns: What was written, or `nil` when nothing was pending.
    @discardableResult
    static func log(
        _ lane: [StrengthExercise],
        on date: Date,
        in context: ModelContext,
        firstWeekday: Int = AppConfiguration.defaultWeekStartDay,
        isLightWeek: Bool = false,
        useMetricUnits: Bool = false
    ) -> PlannedDayLogResult? {
        let allRecords = (try? context.fetch(FetchDescriptor<StrengthRecord>())) ?? []
        let todo = pending(lane, on: date, records: allRecords)
        guard !todo.isEmpty else { return nil }
        let targets = StrengthSlotResolver.targets(for: todo, in: context, now: date, firstWeekday: firstWeekday)
        for slot in todo {
            let target = targets[slot.id] ?? LiftTarget(slot: slot)
            StrengthLiftRegistry.findOrCreate(for: target, metric: target.defaultMetric, in: context)
        }
        let lifts = (try? context.fetch(FetchDescriptor<StrengthLift>())) ?? []
        let made = records(for: todo, targets: targets, on: date, lifts: lifts, records: allRecords,
                           isLightWeek: isLightWeek, useMetricUnits: useMetricUnits)
        var bests: [String] = []
        for (slot, record) in zip(todo, made) {
            let previous = allRecords.filter { $0.liftKey == record.liftKey }
                + made.prefix { $0.id != record.id }.filter { $0.liftKey == record.liftKey }
            if StrengthPersonalBest.isNewBest(record, previous: previous) {
                bests.append(targets[slot.id]?.name ?? slot.name)
            }
            context.insert(record)
            StrengthLiftRegistry.rememberDefaults(after: record, in: context)
        }
        return PlannedDayLogResult(
            recordIDs: made.map(\.id),
            slotIDs: todo.map(\.id),
            date: date,
            newBests: bests
        )
    }

    /// Removes exactly the records a tap wrote.
    /// - Parameters:
    ///   - result: The tap to undo.
    ///   - context: The context to delete from.
    static func undo(_ result: PlannedDayLogResult, in context: ModelContext) {
        let ids = result.recordIDs
        let descriptor = FetchDescriptor<StrengthRecord>(predicate: #Predicate { ids.contains($0.id) })
        for record in (try? context.fetch(descriptor)) ?? [] {
            context.delete(record)
        }
    }
}
