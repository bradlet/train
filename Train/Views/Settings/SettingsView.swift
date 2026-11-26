//
//  SettingsView.swift
//  Train
//
//  App-wide preferences sheet, opened from the gear on every tab. Edits the
//  singleton `AppConfiguration`, and hosts Data (import, export, Sheets
//  sync) until the Connections dashboard (#23).
//

import SwiftUI
import SwiftData

/// A form for app-wide preferences: workout week start day and units.
///
/// The week-start picker only affects weekly aggregation math (weekly
/// mileage buckets, "This Week" stats); calendar grids stay visually
/// Sunday-first regardless.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var configurations: [AppConfiguration]
    @Query private var allExercises: [Exercise]

    /// Recorded exercises, most recent first, for CSV export. `workout !=
    /// nil` can't be a `#Predicate`, so this filters in memory.
    private var completedExercises: [Exercise] {
        allExercises.filter(\.isCompleted).sorted { $0.date > $1.date }
    }

    /// A type's inclusion change waiting on "apply to past workouts?".
    @State private var pendingInclusion: PendingInclusion?

    /// Weekday display names indexed by Calendar weekday - 1 (Sunday first).
    private static let weekdaySymbols = Calendar.current.weekdaySymbols

    var body: some View {
        NavigationStack {
            Form {
                if let config = configurations.first {
                    @Bindable var config = config
                    Section {
                        Picker("Week starts on", selection: $config.weekStartDay) {
                            ForEach(1...7, id: \.self) { weekday in
                                Text(Self.weekdaySymbols[weekday - 1]).tag(weekday)
                            }
                        }
                        .accessibilityIdentifier("settings.weekStartDay")
                    } header: {
                        Text("Training Week")
                    } footer: {
                        Text("Weekly mileage and stats count workouts from this day. The calendar layout stays Sunday-first.")
                    }
                    Section("Units") {
                        Toggle("Use metric units (km)", isOn: $config.useMetricUnits)
                            .accessibilityIdentifier("settings.useMetricUnits")
                    }
                    trainingSection(config)
                }
                WorkoutDataSection(completedExercises: completedExercises)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.doneButton")
                }
            }
            .onChange(of: configurations.first?.weekStartDay) { saveChanges() }
            .onChange(of: configurations.first?.useMetricUnits) { saveChanges() }
            .onAppear { ensureConfigurationExists() }
        }
    }

    /// Per-type "counts toward my training" defaults (#17). Flipping one
    /// asks whether to rewrite that type's past workouts too.
    private func trainingSection(_ config: AppConfiguration) -> some View {
        Section {
            ForEach(ExerciseType.allCases) { type in
                Toggle(isOn: Binding(
                    get: { TrainingInclusion.counts(type, excluded: config.trainingExcludedTypes) },
                    set: { pendingInclusion = PendingInclusion(type: type, counts: $0) }
                )) {
                    Label(type.rawValue, systemImage: type.systemImage)
                }
                .accessibilityIdentifier("settings.training.\(type.rawValue)")
            }
        } header: {
            Text("My Training")
        } footer: {
            Text("New workouts of a type that's off are tracked but don't count toward mileage and stats. You can still change it on any workout.")
        }
        .confirmationDialog(
            pendingInclusion.map { "\($0.counts ? "Count" : "Stop counting") \($0.type.rawValue.lowercased()) workouts?" } ?? "",
            isPresented: Binding(get: { pendingInclusion != nil }, set: { if !$0 { pendingInclusion = nil } }),
            titleVisibility: .visible,
            presenting: pendingInclusion
        ) { pending in
            Button("Past and New Workouts") { applyInclusion(pending, toPast: true, config: config) }
                .accessibilityIdentifier("settings.training.applyPast")
            Button("New Workouts Only") { applyInclusion(pending, toPast: false, config: config) }
                .accessibilityIdentifier("settings.training.newOnly")
            Button("Cancel", role: .cancel) { pendingInclusion = nil }
        }
    }

    /// Saves a type's new default and, when asked, rewrites its past workouts.
    private func applyInclusion(_ pending: PendingInclusion, toPast: Bool, config: AppConfiguration) {
        var excluded = config.trainingExcludedTypes
        if pending.counts { excluded.remove(pending.type) } else { excluded.insert(pending.type) }
        config.trainingExcludedTypes = excluded
        if toPast {
            TrainingInclusion.applyToPast(pending.type, counts: pending.counts, exercises: allExercises)
        }
        pendingInclusion = nil
        saveChanges()
    }

    /// Persists preference edits immediately so other devices sync promptly.
    private func saveChanges() {
        try? modelContext.save()
    }

    /// Creates the singleton AppConfiguration if it doesn't exist yet
    /// (mirrors `ContentView.ensureConfigurationExists`; matters for a
    /// fresh install where this sheet appears before any workout is saved,
    /// and for previews).
    private func ensureConfigurationExists() {
        if configurations.isEmpty {
            modelContext.insert(AppConfiguration())
        }
    }
}

/// A per-type inclusion change awaiting confirmation.
struct PendingInclusion: Identifiable, Equatable {
    let type: ExerciseType
    let counts: Bool
    var id: String { type.rawValue }
}

#Preview {
    SettingsView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
