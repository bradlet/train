//
//  LiftMetric.swift
//  Train
//
//  The one number a lift is tracked by: weight, reps, time, or distance. Each
//  lift declares a primary metric (library JSON or the custom-exercise form),
//  and every `StrengthRecord` stores the metric it was logged with, so a later
//  change to the lift never reinterprets old values.
//
//  Values are stored in one internal unit per metric — pounds, a rep count,
//  seconds, miles — mirroring the app's miles-internally convention, and
//  converted only for display. Strength distances are short (sled pushes,
//  carries), so distance displays in yards / metres rather than miles / km.
//

import Foundation

/// What a lift's single recorded number measures.
enum LiftMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case weight
    case reps
    case time
    case distance

    var id: String { rawValue }

    /// Yards per mile.
    static let yardsPerMile: Double = 1760
    /// Metres per mile.
    static let metersPerMile: Double = 1609.344

    /// Label for pickers, e.g. "Weight".
    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .reps: return "Reps"
        case .time: return "Time"
        case .distance: return "Distance"
        }
    }

    /// SF Symbol representing the metric.
    var systemImage: String {
        switch self {
        case .weight: return "scalemass"
        case .reps: return "repeat"
        case .time: return "stopwatch"
        case .distance: return "ruler"
        }
    }

    /// Whether a record of this metric also names a `LiftMeasurement`
    /// (max / average / …). Only weight and reps vary across sets.
    var usesMeasurement: Bool {
        self == .weight || self == .reps
    }

    /// Display unit suffix for value entry, e.g. "lb", "reps", "m". Time is
    /// entered as minutes and seconds, so it has no single suffix.
    /// - Parameter metric: Whether the user prefers metric units.
    func unitLabel(metric: Bool) -> String {
        switch self {
        case .weight: return metric ? "kg" : "lb"
        case .reps: return "reps"
        case .time: return ""
        case .distance: return metric ? "m" : "yd"
        }
    }

    /// The ± stepper increment in display units: 5 lb / 2.5 kg, 1 rep,
    /// 15 seconds, 10 yd / 10 m.
    /// - Parameter metric: Whether the user prefers metric units.
    func stepIncrement(metric: Bool) -> Double {
        switch self {
        case .weight: return metric ? 2.5 : 5
        case .reps: return 1
        case .time: return 15
        case .distance: return 10
        }
    }

    /// Converts a stored value to the display unit (kg/lb, reps, seconds,
    /// m/yd).
    /// - Parameters:
    ///   - stored: Value in the internal unit.
    ///   - metric: Whether the user prefers metric units.
    func displayValue(fromStored stored: Double, metric: Bool) -> Double {
        switch self {
        case .weight: return stored.toDisplayWeight(metric: metric)
        case .reps, .time: return stored
        case .distance: return stored * (metric ? Self.metersPerMile : Self.yardsPerMile)
        }
    }

    /// Converts a display-unit value back to the internal unit.
    /// - Parameters:
    ///   - display: Value in the display unit.
    ///   - metric: Whether the value was entered in metric units.
    func storedValue(fromDisplay display: Double, metric: Bool) -> Double {
        switch self {
        case .weight: return display.fromDisplayWeight(metric: metric)
        case .reps, .time: return display
        case .distance: return display / (metric ? Self.metersPerMile : Self.yardsPerMile)
        }
    }

    /// Formats a stored value for display, e.g. "185 lb", "12 reps", "1:30",
    /// "40 m". A `nil` value is a session logged as done with no number.
    /// - Parameters:
    ///   - value: Value in the internal unit, or `nil` for "done".
    ///   - metric: Whether to display in metric units.
    func formatted(_ value: Double?, metric: Bool) -> String {
        guard let value else { return "Done" }
        switch self {
        case .weight:
            return value.formattedWeight(metric: metric)
        case .reps:
            let count = Int(value.rounded())
            return count == 1 ? "1 rep" : "\(count) reps"
        case .time:
            return Self.formattedClock(seconds: Int(value.rounded()))
        case .distance:
            let display = Int(displayValue(fromStored: value, metric: metric).rounded())
            return "\(display) \(unitLabel(metric: metric))"
        }
    }

    /// Formats whole seconds as "m:ss", or "h:mm:ss" from an hour up.
    /// - Parameter seconds: Non-negative duration in seconds.
    static func formattedClock(seconds: Int) -> String {
        let total = Swift.max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
