//
//  StrengthView.swift
//  Train
//
//  The Strength tab: Plan (the weekly board, `StrengthTrainingView`) and
//  Progress behind one segmented control, mirroring the Cardio tab (#12).
//  Progress is a placeholder until the lift list and charts land (#16).
//

import SwiftUI
import SwiftData

/// The Strength tab: Plan | Progress.
struct StrengthView: View {
    /// The visible segment; Plan by default.
    @State private var segment: TrainingSegment = .plan

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .plan: StrengthTrainingView()
                case .progress: StrengthProgressPlaceholder()
                }
            }
            .navigationTitle("Strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TrainingSegmentPicker(selection: $segment, identifier: "strength.segment")
                }
            }
            .settingsToolbarButton()
        }
    }
}

/// Strength → Progress until the lift list, charts and PRs arrive (#16).
struct StrengthProgressPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("Lift progress is coming", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Charts, personal bests and the history of every lift will live here. Everything you record is already being kept.")
        }
        .accessibilityIdentifier("strengthProgress.placeholder")
    }
}

#Preview {
    StrengthView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
