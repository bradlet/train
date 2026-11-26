//
//  CardioView.swift
//  Train
//
//  The Cardio tab: Plan (the weekly calendar, `AerobicTrainingView`) and
//  Progress (stats, calendar and workout log, `HistoryView`) behind one
//  segmented control — the same shape as the Strength tab (#12). Owns the
//  navigation bar; each segment adds its own toolbar items.
//

import SwiftUI
import SwiftData

/// The Cardio tab: Plan | Progress.
struct CardioView: View {
    /// The visible segment; Plan by default.
    @State private var segment: TrainingSegment = .plan
    @Environment(\.planRouter) private var planRouter

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .plan: AerobicTrainingView()
                case .progress: HistoryView()
                }
            }
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TrainingSegmentPicker(selection: $segment, identifier: "cardio.segment")
                }
            }
            .settingsToolbarButton()
            // A day opened from Home's week strip shows on Plan (#19).
            .onChange(of: planRouter.cardioDay != nil, initial: true) { _, pending in
                if pending { segment = .plan }
            }
        }
    }
}

#Preview {
    CardioView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
