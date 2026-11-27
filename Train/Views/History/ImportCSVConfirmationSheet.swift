//
//  ImportCSVConfirmationSheet.swift
//  Train
//
//  Sheet shown after the athlete picks CSV files to import (#21). Summarizes
//  what will be imported per kind (cardio, strength), what is already in the
//  app and will be skipped, and makes the cardio distance unit explicit and
//  prominent, since the cardio file does not name its unit. Strength rows name
//  their own unit, so they need no choice.
//

import SwiftUI

/// Confirmation sheet for parsed CSV files. Does not write to the store.
struct ImportCSVConfirmationSheet: View {
    /// The parsed files.
    let parsed: TrainingCSVBundle.Parsed
    /// Records already in the app, which the import will skip.
    let duplicateCount: Int
    @Binding var unit: WorkoutCSVDistanceUnit
    let onCancel: () -> Void
    let onConfirm: () -> Void

    /// Records the import will add.
    private var newCount: Int {
        max(0, parsed.cardio.rows.count + parsed.strength.records.count - duplicateCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                if !parsed.cardio.rows.isEmpty {
                    unitSection
                }
                if !parsed.failures.isEmpty {
                    Section("Not Read") {
                        ForEach(parsed.failures, id: \.self) { failure in
                            Text(failure).font(.caption)
                        }
                    }
                }
                if parsed.skippedCount > 0 {
                    skippedSection
                }
            }
            .navigationTitle("Import Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(newCount)", action: onConfirm)
                        .disabled(newCount == 0)
                        .accessibilityIdentifier("importCSV.confirm")
                }
            }
        }
    }

    /// Files read and what they hold.
    private var summarySection: some View {
        Section {
            ForEach(parsed.fileNames, id: \.self) { name in
                Label(name, systemImage: "doc.text")
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !parsed.cardio.rows.isEmpty {
                LabeledContent("Cardio workouts", value: "\(parsed.cardio.rows.count)")
            }
            if !parsed.strength.records.isEmpty {
                LabeledContent("Strength sessions", value: "\(parsed.strength.records.count)")
            }
        } footer: {
            if duplicateCount > 0 {
                Text("\(duplicateCount) already in Train will be skipped.")
            }
        }
    }

    /// The cardio distance unit, chosen explicitly.
    private var unitSection: some View {
        Section {
            Picker("Distance values are in", selection: $unit) {
                ForEach(WorkoutCSVDistanceUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            Text("Cardio distances will be read as **\(unit.displayName.lowercased())**. Switch if the file was exported with the other unit. Strength rows name their own unit.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Cardio Distance Unit")
        }
    }

    /// Rows that failed validation.
    private var skippedSection: some View {
        let skipped = parsed.cardio.skipped + parsed.strength.skipped
        return Section {
            DisclosureGroup("\(skipped.count) row\(skipped.count == 1 ? "" : "s") skipped") {
                ForEach(Array(skipped.prefix(10).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Line \(row.line)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(row.reason)
                            .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
                if skipped.count > 10 {
                    Text("…and \(skipped.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Skipped Rows")
        } footer: {
            Text("These rows failed validation and will not be imported.")
        }
    }
}

#Preview {
    @Previewable @State var unit: WorkoutCSVDistanceUnit = .miles
    ImportCSVConfirmationSheet(
        parsed: TrainingCSVBundle.Parsed(
            cardio: WorkoutCSVParseResult(rows: [], skipped: [.init(line: 3, reason: "invalid date 'yesterday'")]),
            fileNames: ["train-cardio-2026-11-27.csv", "train-strength-2026-11-27.csv"]
        ),
        duplicateCount: 2,
        unit: $unit,
        onCancel: {},
        onConfirm: {}
    )
}
