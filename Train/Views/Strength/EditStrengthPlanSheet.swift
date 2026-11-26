//
//  EditStrengthPlanSheet.swift
//  Train
//
//  Small sheet for setting an exercise's planned set structure (e.g. 3 sets
//  of 8 reps). This is plan-only data the user keeps in mind through the
//  week — it never touches the recorded `StrengthWorkout` history.
//
//  The fields come from `StrengthPlanFields`, shared with the add-from-library
//  flow so both surfaces stay identical. A single-lift card also takes an
//  optional target (#20): blank keeps the lift trend-only; changes go through
//  `StrengthTargetEditor`, which logs them for the chart.
//

import SwiftUI
import SwiftData

/// Sheet for editing a `StrengthExercise`'s planned sets × reps.
struct EditStrengthPlanSheet: View {
    /// The exercise whose plan is being edited.
    let exercise: StrengthExercise

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits

    @State private var draft: StrengthPlanDraft
    /// The target, edited with the same value editor as recording.
    @State private var targetDraft = StrengthRecordDraft(metric: .weight)
    @State private var didLoadTarget = false

    /// Creates the sheet, seeding the draft from the existing plan (or a
    /// switched-off 3×8 when the exercise has no plan yet).
    /// - Parameter exercise: The exercise whose plan is being edited.
    init(exercise: StrengthExercise) {
        self.exercise = exercise
        _draft = State(
            initialValue: StrengthPlanDraft(
                plannedSets: exercise.plannedSets,
                plannedReps: exercise.plannedReps
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                StrengthPlanFields(draft: $draft)
                if !exercise.isGroup {
                    Section {
                        StrengthValueEditor(draft: $targetDraft, identifierPrefix: "editPlan.target")
                    } header: {
                        Text("Target")
                    } footer: {
                        Text("Optional. Recording starts on it, and after two sessions at or above it you'll be offered a small step up. Leave blank to just track the trend.")
                    }
                }
            }
            .onAppear {
                guard !didLoadTarget else { return }
                didLoadTarget = true
                let metric = StrengthPrefill.resolve(for: exercise, in: modelContext).metric
                targetDraft = StrengthRecordDraft(metric: metric)
                if let target = exercise.targetValue {
                    targetDraft.setValue(stored: target, useMetricUnits: useMetricUnits)
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.apply(to: exercise)
                        saveTarget()
                        dismiss()
                    }
                    .disabled(!targetDraft.canSave(useMetricUnits: useMetricUnits))
                    .accessibilityIdentifier("editPlan.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Writes the target (blank clears it) through the editor, which logs it.
    private func saveTarget() {
        guard !exercise.isGroup else { return }
        let value: Double?
        switch targetDraft.entry(useMetricUnits: useMetricUnits) {
        case .value(let parsed): value = parsed
        case .done: value = nil
        case .invalid: return
        }
        StrengthTargetEditor.setTarget(value, on: exercise, metric: targetDraft.metric, in: modelContext)
    }
}

#Preview {
    EditStrengthPlanSheet(
        exercise: StrengthExercise(name: "Back Squat", muscleGroup: .quads, plannedSets: 3, plannedReps: 8)
    )
    .modelContainer(ModelContainerFactory.makePreviewContainer())
}
