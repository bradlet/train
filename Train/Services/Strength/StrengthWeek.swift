//
//  StrengthWeek.swift
//  Train
//
//  The board's "done this week" rules (#15): which cards were recorded in
//  the current week, and which active cards from earlier days this week are
//  still to do. The week follows the athlete's week-start setting, so the
//  checkmarks reset on their own when it rolls over and nothing carries
//  across a week boundary. Pure and unit-tested, like `StrengthLiftRegistry`.
//

import Foundation

/// Current-week views over the board and its records.
enum StrengthWeek {

    /// The week containing `now`, from midnight on the configured first
    /// weekday to midnight seven days later (exclusive).
    /// - Parameters:
    ///   - now: Any moment in the week.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func interval(containing now: Date, firstWeekday: Int) -> DateInterval {
        let start = now.startOfWeek(firstWeekday: firstWeekday)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? now
        return DateInterval(start: start, end: end)
    }

    /// The latest record per card (`slotID`) dated in the current week.
    /// Records without a card, or outside the week, are ignored: a ✓ means
    /// *this card* was done *this week*.
    /// - Parameters:
    ///   - records: All strength records.
    ///   - now: Any moment in the current week.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func recordsBySlot(
        _ records: [StrengthRecord],
        now: Date,
        firstWeekday: Int
    ) -> [UUID: StrengthRecord] {
        let week = interval(containing: now, firstWeekday: firstWeekday)
        var latest: [UUID: StrengthRecord] = [:]
        for record in records {
            guard let slotID = record.slotID, contains(week, record.date) else { continue }
            if let current = latest[slotID], current.date >= record.date { continue }
            latest[slotID] = record
        }
        return latest
    }

    /// The date a weekday lane falls on in the current week.
    /// - Parameters:
    ///   - weekdayIndex: The lane (Sunday=0 ... Saturday=6).
    ///   - now: Any moment in the current week.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func date(ofLane weekdayIndex: Int, now: Date, firstWeekday: Int) -> Date {
        let start = now.startOfWeek(firstWeekday: firstWeekday)
        // `firstWeekday` is 1-based; lanes are 0-based.
        let offset = (weekdayIndex - (firstWeekday - 1) + 7) % 7
        return Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
    }

    /// Active cards from lanes earlier in the current week than today that
    /// have no record this week — the "Still to do this week" list. Today's
    /// lane is excluded (it's already Today's work); offloaded cards are out
    /// of the plan. Ordered by lane date, then board order.
    /// - Parameters:
    ///   - slots: Every strength card.
    ///   - records: All strength records.
    ///   - now: The current moment.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func carryover(
        _ slots: [StrengthExercise],
        records: [StrengthRecord],
        now: Date,
        firstWeekday: Int
    ) -> [StrengthExercise] {
        let today = now.startOfDay
        let done = recordsBySlot(records, now: now, firstWeekday: firstWeekday)
        var missed: [(slot: StrengthExercise, date: Date)] = []
        for slot in slots where !slot.isOffloaded && done[slot.id] == nil {
            let laneDate = date(ofLane: slot.weekdayIndex, now: now, firstWeekday: firstWeekday)
            if laneDate < today { missed.append((slot, laneDate)) }
        }
        missed.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.slot.sortOrder < rhs.slot.sortOrder
        }
        return missed.map(\.slot)
    }

    /// Half-open containment, so a record at midnight starting next week
    /// belongs to next week only.
    private static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
}

// MARK: - Personal best

/// "New best" detection for the PR badge (#15, W2). Trend-only: a best is
/// compared within one lift, metric and measurement — an Average never
/// competes with a Max — and higher is better for every metric (more weight,
/// reps, time held, distance).
enum StrengthPersonalBest {

    /// Whether `record` beats every earlier valued record of its lift in the
    /// same metric and measurement. A first-ever value is not a "best" —
    /// there is nothing to beat — and a "done" record never is.
    /// - Parameters:
    ///   - record: The record being saved.
    ///   - previous: The lift's existing records (`record` itself excluded).
    static func isNewBest(_ record: StrengthRecord, previous: [StrengthRecord]) -> Bool {
        guard let value = record.value else { return false }
        let comparable = previous.compactMap { other -> Double? in
            guard other.id != record.id,
                  other.liftKey == record.liftKey,
                  other.metric == record.metric,
                  other.measurement == record.measurement
            else { return nil }
            return other.value
        }
        guard let best = comparable.max() else { return false }
        return value > best
    }
}
