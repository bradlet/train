//
//  StrengthView.swift
//  Train
//
//  The Strength tab: Plan (the weekly board, `StrengthTrainingView`) and
//  Progress behind one segmented control, mirroring the Cardio tab (#12).
//  Progress is the lift list (`StrengthProgressView`, #16). The tab's stack
//  resolves every `StrengthProgressRoute`, so lift and group screens push
//  the same way from either segment.
//

import SwiftUI
import SwiftData

/// The Strength tab: Plan | Progress.
struct StrengthView: View {
    /// The visible segment; Plan by default.
    @State private var segment: TrainingSegment = .plan
    @Environment(\.planRouter) private var planRouter

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .plan: StrengthTrainingView()
                case .progress: StrengthProgressView()
                }
            }
            .navigationDestination(for: StrengthProgressRoute.self) { route in
                StrengthProgressDestination(route: route)
            }
            .navigationTitle("Strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TrainingSegmentPicker(selection: $segment, identifier: "strength.segment")
                }
            }
            .settingsToolbarButton()
            // A day opened from Home's week strip shows on Plan (#19).
            .onChange(of: planRouter.strengthWeekday != nil, initial: true) { _, pending in
                if pending { segment = .plan }
            }
        }
    }
}

#Preview {
    StrengthView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
