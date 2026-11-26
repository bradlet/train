//
//  LiftMeasurement.swift
//  Train
//
//  Which single number a strength record captures for a session — the max,
//  the average across sets, the first or last set, or the min. Strength stays
//  high-level (one number per session, never per-set logs), so naming what
//  the number represents lets e.g. a top set and an average working weight be
//  trended separately. Applies to the weight and reps metrics only (see
//  `LiftMetric.usesMeasurement`); time and distance record one value each.
//

import Foundation

/// The kind of measurement captured by a `StrengthRecord`.
enum LiftMeasurement: String, Codable, CaseIterable, Identifiable, Sendable {
    case max
    case average
    case firstSet
    case lastSet
    case min

    var id: String { rawValue }

    /// The measurement a lift starts with before it has a remembered default:
    /// Average, the honest picture of a session's working sets.
    static let starting: LiftMeasurement = .average

    /// Full label for pickers, e.g. "First Set". Neutral wording so it reads
    /// correctly for both weight and reps.
    var displayName: String {
        switch self {
        case .max: return "Max"
        case .average: return "Average"
        case .firstSet: return "First Set"
        case .lastSet: return "Last Set"
        case .min: return "Min"
        }
    }

    /// Short label for compact card display, e.g. "Avg".
    var shortLabel: String {
        switch self {
        case .max: return "Max"
        case .average: return "Avg"
        case .firstSet: return "First"
        case .lastSet: return "Last"
        case .min: return "Min"
        }
    }
}
