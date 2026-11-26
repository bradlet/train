//
//  StrengthRecord.swift
//  Train
//
//  One recorded strength session for a lift: when, the single number it was
//  tracked by (or none — "done"), what that number measures, and which board
//  card it was logged from. Each record is its own row so two devices logging
//  the same lift both survive a CloudKit sync (a JSON blob on the lift would
//  be last-writer-wins). Links are keys, not relationships: `liftKey` to the
//  lift, `slotID` to the `StrengthExercise` card, which may since be gone.
//

import Foundation
import SwiftData

@Model
final class StrengthRecord {
    /// Stable identifier for list identity, editing and deletion.
    var id: UUID = UUID()
    /// The lift this record belongs to; see `StrengthLiftKey`.
    var liftKey: String = ""
    /// The `StrengthExercise.id` of the card it was logged from, so a card's
    /// weekly ✓ and missed-lift carryover are per card. `nil` when logged
    /// from nowhere in particular.
    var slotID: UUID? = nil
    /// The day the session was performed.
    var date: Date = Date()
    /// The recorded number in `metric`'s internal unit (lb, reps, seconds,
    /// miles), or `nil` for a session logged as done without one. Charts
    /// must show `nil` as a gap, never as 0.
    var value: Double? = nil
    /// Raw metric the value was recorded in. Access through `metric`.
    private var metricRaw: String = LiftMetric.weight.rawValue
    /// Raw measurement (max, average, …), `nil` for time and distance or a
    /// value-less record. Access through `measurement`.
    private var measurementRaw: String? = nil
    /// Optional post-session notes.
    var notes: String = ""
    /// Whether it was logged during a light week (#20), so trends can tell
    /// a planned dip from a regression.
    var isLight: Bool = false

    /// The metric the value was recorded in. Stored per record so a later
    /// change to the lift's metric never reinterprets old values. Unknown
    /// raw values read as weight.
    var metric: LiftMetric {
        get { LiftMetric(rawValue: metricRaw) ?? .weight }
        set { metricRaw = newValue.rawValue }
    }

    /// What the value represents, for weight and reps. Unknown raw values
    /// read as `nil`.
    var measurement: LiftMeasurement? {
        get { measurementRaw.flatMap(LiftMeasurement.init(rawValue:)) }
        set { measurementRaw = newValue?.rawValue }
    }

    /// Creates a record. A measurement is dropped for metrics that don't use
    /// one (time, distance).
    /// - Parameters:
    ///   - liftKey: The lift this record belongs to.
    ///   - slotID: The card it was logged from, if any.
    ///   - date: The day the session was performed.
    ///   - value: The number in the metric's internal unit, or `nil` for done.
    ///   - metric: The metric the value is recorded in.
    ///   - measurement: What the value represents (weight and reps only).
    ///   - notes: Optional notes.
    init(
        liftKey: String,
        slotID: UUID? = nil,
        date: Date = Date(),
        value: Double? = nil,
        metric: LiftMetric = .weight,
        measurement: LiftMeasurement? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.liftKey = liftKey
        self.slotID = slotID
        self.date = date
        self.value = value
        self.metric = metric
        self.measurement = metric.usesMeasurement ? measurement : nil
        self.notes = notes
    }

    /// One-line summary without the date, e.g. "185 lb · Max", "1:30",
    /// "Done".
    /// - Parameter metric: Whether to display in metric units.
    func summary(useMetricUnits: Bool) -> String {
        let valueText = self.metric.formatted(value, metric: useMetricUnits)
        guard value != nil, let measurement else { return valueText }
        return "\(valueText) · \(measurement.shortLabel)"
    }
}
