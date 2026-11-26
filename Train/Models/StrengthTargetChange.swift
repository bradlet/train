//
//  StrengthTargetChange.swift
//  Train
//
//  One change to a card's target (#20): the plan's changelog. The lift
//  detail chart draws these as a target step line behind the records, so
//  the plan's evolution and the results sit in one picture. Rows (never a
//  blob) so two devices' edits both survive sync; CloudKit-safe defaults.
//

import Foundation
import SwiftData

@Model
final class StrengthTargetChange {
    var id: UUID = UUID()
    /// The lift the target is for.
    var liftKey: String = ""
    /// The card it was set on.
    var slotID: UUID? = nil
    /// When it changed.
    var date: Date = Date()
    /// The new target in the metric's internal unit, or `nil` when cleared.
    var value: Double? = nil
    /// Raw `LiftMetric` the value is in. Access through `metric`.
    private var metricRaw: String = LiftMetric.weight.rawValue

    /// The metric the value is in.
    var metric: LiftMetric {
        get { LiftMetric(rawValue: metricRaw) ?? .weight }
        set { metricRaw = newValue.rawValue }
    }

    /// Creates a change.
    init(liftKey: String, slotID: UUID?, date: Date = Date(), value: Double?, metric: LiftMetric) {
        self.id = UUID()
        self.liftKey = liftKey
        self.slotID = slotID
        self.date = date
        self.value = value
        self.metric = metric
    }
}
