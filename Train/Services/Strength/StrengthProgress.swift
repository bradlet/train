//
//  StrengthProgress.swift
//  Train
//
//  The pure rules behind Strength → Progress (#16): one summary per lift
//  with history (sparkline, latest, best, last done), the lift list's
//  sections and search, per-measurement chart series with personal-best
//  markers, the week's headline, a movement group's rotation strip, and
//  record edits. Unit-tested; views only lay these out.
//

import Foundation
import SwiftData

/// One lift in the Progress list.
struct LiftSummary: Identifiable, Equatable {
    let liftKey: String
    let name: String
    let muscleGroup: MuscleGroup
    /// The lift's metric (its latest record's when the lift row is missing).
    let metric: LiftMetric
    /// The measurement the summary is about: the lift's default, else its
    /// latest valued record's. `nil` for time and distance.
    let measurement: LiftMeasurement?
    /// The most recent valued record's value in that metric and measurement.
    let latestValue: Double?
    /// The best value in that metric and measurement.
    let bestValue: Double?
    /// The most recent record of any kind (a "done" counts).
    let lastDone: Date
    /// How many records the lift has.
    let recordCount: Int
    /// Recent values in that metric and measurement, oldest first (at most
    /// `StrengthProgress.sparklineLength`).
    let sparkline: [Double]

    var id: String { liftKey }
}

/// One point of a lift chart.
struct LiftChartPoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let value: Double
    /// Whether this record set a new best when it was logged.
    let isPersonalBest: Bool
}

/// One line of a lift chart: a measurement's valued records, oldest first.
struct LiftChartSeries: Identifiable, Equatable {
    /// `nil` for time and distance, which have one series.
    let measurement: LiftMeasurement?
    let points: [LiftChartPoint]

    var id: String { measurement?.rawValue ?? "value" }
    /// Legend label.
    var label: String { measurement?.displayName ?? "Value" }
}

/// Pure Strength → Progress rules.
enum StrengthProgress {

    /// Points in a list row's sparkline.
    static let sparklineLength = 12

    // MARK: Lift list

    /// A summary for every lift with at least one record — including lifts
    /// no longer on the board — most recently done first.
    /// - Parameters:
    ///   - lifts: All lifts (duplicates resolve to the oldest).
    ///   - records: All records.
    static func summaries(lifts: [StrengthLift], records: [StrengthRecord]) -> [LiftSummary] {
        let byKey = Dictionary(grouping: records, by: \.liftKey)
        return byKey.compactMap { key, history -> LiftSummary? in
            let newestFirst = history.sorted { $0.date > $1.date }
            guard let newest = newestFirst.first else { return nil }
            let lift = StrengthLiftRegistry.lift(forKey: key, in: lifts)
            let metric = lift?.primaryMetric ?? newest.metric
            let measurement: LiftMeasurement? = metric.usesMeasurement
                ? (lift?.defaultMeasurement
                   ?? newestFirst.first { $0.metric == metric && $0.value != nil }?.measurement
                   ?? .starting)
                : nil
            let matching = newestFirst.filter { record in
                record.metric == metric && record.value != nil
                    && (!metric.usesMeasurement || record.measurement == measurement)
            }
            let values = matching.compactMap(\.value)
            return LiftSummary(
                liftKey: key,
                name: lift?.name ?? displayName(forKey: key),
                muscleGroup: lift?.muscleGroup ?? .other,
                metric: metric,
                measurement: measurement,
                latestValue: values.first,
                bestValue: values.max(),
                lastDone: newest.date,
                recordCount: history.count,
                sparkline: Array(values.prefix(sparklineLength).reversed())
            )
        }
        .sorted { $0.lastDone > $1.lastDone }
    }

    /// A readable name for a key with no lift row: the library entry's name,
    /// or the name a "name:" key was made from.
    static func displayName(forKey key: String) -> String {
        if key.hasPrefix(StrengthLiftKey.namePrefix) {
            return String(key.dropFirst(StrengthLiftKey.namePrefix.count)).capitalized
        }
        return MovementGroupCatalog.bundledLibrary.first { $0.id == key }?.name ?? key
    }

    /// The list's sections: lifts matching the search and muscle-group
    /// filter, grouped by muscle group in `MuscleGroup` order, each section
    /// by name.
    /// - Parameters:
    ///   - summaries: All summaries.
    ///   - searchText: Name filter (case-insensitive); empty matches all.
    ///   - muscleGroup: Group filter; `nil` matches all.
    static func sections(
        _ summaries: [LiftSummary],
        searchText: String,
        muscleGroup: MuscleGroup?
    ) -> [(group: MuscleGroup, lifts: [LiftSummary])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let shown = summaries.filter { summary in
            (muscleGroup == nil || summary.muscleGroup == muscleGroup)
                && (query.isEmpty || summary.name.localizedCaseInsensitiveContains(query))
        }
        return MuscleGroup.allCases.compactMap { group in
            let lifts = shown.filter { $0.muscleGroup == group }.sorted { $0.name < $1.name }
            return lifts.isEmpty ? nil : (group, lifts)
        }
    }

    // MARK: Lift detail

    /// The ids of records that set a new best when logged: walking records
    /// in date order, a valued record beating every earlier valued record
    /// of its metric and measurement (the first value is not a best — the
    /// same rule as the save-time "New best" banner).
    /// - Parameter records: One lift's records.
    static func personalBests(_ records: [StrengthRecord]) -> Set<UUID> {
        var best: [String: Double] = [:]
        var result = Set<UUID>()
        for record in records.sorted(by: { $0.date < $1.date }) {
            guard let value = record.value else { continue }
            let key = record.metric.rawValue + "|" + (record.measurement?.rawValue ?? "")
            if let previous = best[key] {
                if value > previous {
                    result.insert(record.id)
                    best[key] = value
                }
            } else {
                best[key] = value
            }
        }
        return result
    }

    /// Chart series for a lift in one metric: a line per measurement (in
    /// `LiftMeasurement` order), valued records only — a "done" record is a
    /// gap, never 0. Records since `since` only, when given.
    /// - Parameters:
    ///   - records: One lift's records.
    ///   - metric: The metric to chart.
    ///   - since: The earliest date to include, or `nil` for all.
    static func series(_ records: [StrengthRecord], metric: LiftMetric, since: Date? = nil) -> [LiftChartSeries] {
        let bests = personalBests(records)
        let shown = records
            .filter { $0.metric == metric && $0.value != nil && (since == nil || $0.date >= since!) }
            .sorted { $0.date < $1.date }
        let measurements: [LiftMeasurement?] = metric.usesMeasurement ? LiftMeasurement.allCases.map { $0 } : [nil]
        return measurements.compactMap { measurement in
            let points = shown
                .filter { !metric.usesMeasurement || $0.measurement == measurement }
                .map { LiftChartPoint(id: $0.id, date: $0.date, value: $0.value!, isPersonalBest: bests.contains($0.id)) }
            return points.isEmpty ? nil : LiftChartSeries(measurement: measurement, points: points)
        }
    }

    // MARK: Summary

    /// This week's strength headline: lift records and distinct training days.
    /// - Parameters:
    ///   - records: All records.
    ///   - now: The current moment.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    static func thisWeek(_ records: [StrengthRecord], now: Date, firstWeekday: Int) -> (lifts: Int, days: Int) {
        let week = StrengthWeek.interval(containing: now, firstWeekday: firstWeekday)
        let inWeek = records.filter { $0.date >= week.start && $0.date < week.end }
        let days = Set(inWeek.map { Calendar.current.startOfDay(for: $0.date) })
        return (inWeek.count, days.count)
    }

    // MARK: Groups

    /// How often each member of a group was done in the last `weeks` weeks,
    /// in member order — the group's rotation strip. A zero highlights a
    /// member the rotation hasn't reached.
    /// - Parameters:
    ///   - group: The group.
    ///   - records: All records.
    ///   - now: The current moment.
    ///   - weeks: How far back to count.
    static func rotationCounts(
        _ group: MovementGroup,
        records: [StrengthRecord],
        now: Date,
        weeks: Int = 8
    ) -> [(member: GroupMember, count: Int)] {
        let since = Calendar.current.date(byAdding: .day, value: -weeks * 7, to: now) ?? now
        let recent = records.filter { $0.date >= since && $0.date <= now }
        let counts = Dictionary(grouping: recent, by: \.liftKey).mapValues(\.count)
        return group.members.map { ($0, counts[$0.liftKey] ?? 0) }
    }

    /// Groups any of whose members have history, for the list's Groups
    /// section, by name.
    static func groupsWithHistory(_ groups: [MovementGroup], records: [StrengthRecord]) -> [MovementGroup] {
        let keys = Set(records.map(\.liftKey))
        return groups.filter { group in group.members.contains { keys.contains($0.liftKey) } }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Editing

/// The one mutation path for an existing strength record (mirrors
/// `WorkoutEditor`): edits go through a `StrengthRecordDraft`, so the
/// record sheet and the edit sheet parse values the same way.
enum StrengthRecordEditor {

    /// A draft holding a record's current values, for the edit form.
    /// - Parameters:
    ///   - record: The record to edit.
    ///   - useMetricUnits: Whether values show in metric units.
    static func draft(for record: StrengthRecord, useMetricUnits: Bool) -> StrengthRecordDraft {
        var draft = StrengthRecordDraft(metric: record.metric, date: record.date)
        if let value = record.value { draft.setValue(stored: value, useMetricUnits: useMetricUnits) }
        draft.measurement = record.measurement ?? .starting
        draft.notes = record.notes
        return draft
    }

    /// Writes a valid draft back onto the record. Returns `false` (and
    /// changes nothing) when the draft's value is invalid. The lift, card
    /// and metric are never changed.
    /// - Parameters:
    ///   - draft: The edited values.
    ///   - record: The record to update.
    ///   - useMetricUnits: Whether values were entered in metric units.
    @discardableResult
    static func apply(_ draft: StrengthRecordDraft, to record: StrengthRecord, useMetricUnits: Bool) -> Bool {
        let value: Double?
        switch draft.entry(useMetricUnits: useMetricUnits) {
        case .invalid: return false
        case .done: value = nil
        case .value(let parsed): value = parsed
        }
        record.date = draft.date
        record.value = value
        record.measurement = value != nil && record.metric.usesMeasurement ? draft.measurement : nil
        record.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    /// Deletes a record.
    static func delete(_ record: StrengthRecord, in context: ModelContext) {
        context.delete(record)
    }
}
