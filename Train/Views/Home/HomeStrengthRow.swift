//
//  HomeStrengthRow.swift
//  Train
//
//  Compact row for one of today's strength exercises on the Home tab, or for
//  a card from earlier this week that is still to do (#15).
//
//  Deliberately not `StrengthExerciseCard`: that card owns drag-and-drop,
//  move-to-day, and offload affordances, which are weekly-board semantics and
//  don't belong on a "what am I doing today" surface. Tapping here records.
//

import SwiftUI

/// One of today's strength exercises, tappable to record a weight.
struct HomeStrengthRow: View {
    let exercise: StrengthExercise
    /// The latest record of this exercise's lift, if any.
    let latestRecord: StrengthRecord?
    /// This card's latest record in the current week — shown as a ✓.
    var weekRecord: StrengthRecord? = nil
    /// The lane's short weekday name when the row is carried over from an
    /// earlier day this week ("Mon"); `nil` for today's lane.
    var carryoverDay: String? = nil
    /// Called when the row is tapped to record a session.
    let onRecord: () -> Void

    @Environment(\.useMetricUnits) private var useMetricUnits

    var body: some View {
        Button(action: onRecord) {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.callout)
                    .foregroundStyle(exercise.muscleGroup.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if let carryoverDay {
                            Text(carryoverDay)
                                .fontWeight(.semibold)
                            Text("•")
                        }
                        Text(exercise.muscleGroup.rawValue)
                        if let plan = exercise.plannedSummary {
                            Text("•")
                            Text(plan)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let thisWeek = weekRecord {
                    Label(
                        thisWeek.metric.formatted(thisWeek.value, metric: useMetricUnits),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("home.strengthWeekCheck.\(exercise.name)")
                } else if let latest = latestRecord {
                    Text(latest.metric.formatted(latest.value, metric: useMetricUnits))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            carryoverDay == nil ? "home.strengthRow.\(exercise.name)" : "home.carryoverRow.\(exercise.name)"
        )
    }
}
