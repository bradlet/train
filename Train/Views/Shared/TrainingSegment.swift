//
//  TrainingSegment.swift
//  Train
//
//  The Plan | Progress split shared by the Cardio and Strength tabs. Both
//  disciplines use the same two segments, so the flows read as siblings.
//

import SwiftUI

/// One half of a discipline tab: planning or reviewing progress.
enum TrainingSegment: String, CaseIterable, Identifiable, Hashable {
    case plan
    case progress

    var id: String { rawValue }

    /// Segment label, e.g. "Plan".
    var title: String {
        switch self {
        case .plan: return "Plan"
        case .progress: return "Progress"
        }
    }
}

/// The segmented Plan | Progress control shown in a discipline tab's
/// navigation bar.
struct TrainingSegmentPicker: View {
    @Binding var selection: TrainingSegment
    /// Accessibility identifier, e.g. "cardio.segment".
    let identifier: String

    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(TrainingSegment.allCases) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .accessibilityIdentifier(identifier)
    }
}
