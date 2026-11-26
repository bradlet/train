//
//  StrengthValueEditor.swift
//  Train
//
//  The value entry for one strength record, shared by the single-lift record
//  sheet and the whole-day sheet: − / + nudges around the text field(s) for
//  the lift's metric (minutes and seconds for time).
//

import SwiftUI

/// − / + nudges around a strength record's value field(s).
struct StrengthValueEditor: View {
    @Binding var draft: StrengthRecordDraft
    /// Prefix for accessibility identifiers, e.g. "recordStrength" gives
    /// "recordStrength.valueField", "recordStrength.increment".
    let identifierPrefix: String

    @Environment(\.useMetricUnits) private var useMetricUnits

    var body: some View {
        HStack(spacing: 12) {
            nudgeButton(by: -1, systemImage: "minus.circle.fill", suffix: "decrement")
            entry
            nudgeButton(by: 1, systemImage: "plus.circle.fill", suffix: "increment")
        }
    }

    /// One stepper button; borderless so several work inside one form row.
    private func nudgeButton(by steps: Int, systemImage: String, suffix: String) -> some View {
        Button {
            draft.nudge(by: steps, useMetricUnits: useMetricUnits)
        } label: {
            Image(systemName: systemImage)
                .font(.title2)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(steps > 0 ? "Increase" : "Decrease")
        .accessibilityIdentifier("\(identifierPrefix).\(suffix)")
    }

    /// The text field(s) for the value.
    @ViewBuilder
    private var entry: some View {
        if draft.metric == .time {
            HStack {
                TextField("Min", text: $draft.minutesText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("\(identifierPrefix).minutesField")
                Text("min").foregroundStyle(.secondary)
                TextField("Sec", text: $draft.secondsText)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("\(identifierPrefix).secondsField")
                Text("sec").foregroundStyle(.secondary)
            }
        } else {
            HStack {
                TextField(draft.metric.displayName, text: $draft.valueText)
                    .keyboardType(draft.metric == .reps ? .numberPad : .decimalPad)
                    .accessibilityIdentifier("\(identifierPrefix).valueField")
                Text(draft.metric.unitLabel(metric: useMetricUnits))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
