//
//  ImportHealthKitSheet.swift
//  Train
//
//  Sheet presented from Settings → Data to import workouts from Apple
//  Health. Requests read authorization on appear, loads recent workouts via
//  `AppleHealthTarget`, and lets the athlete multi-select with SwiftUI's
//  native `EditMode`. Workouts already in the app (by HealthKit UUID) are
//  shown as imported and can't be picked again. The selection is committed
//  through `TrainingImporter`, which logs it for Undo.
//

import SwiftUI
import SwiftData

/// How many days of history to pull from HealthKit by default.
private let importLookbackDays: TimeInterval = 30

/// Sheet that lists recent Apple Health workouts and lets the user import
/// selected ones into the app's SwiftData store.
struct ImportHealthKitSheet: View {
    @Environment(\.healthKitImport) private var service
    @Environment(\.modelContext) private var modelContext
    @Environment(\.trainingExcludedTypes) private var trainingExcludedTypes
    @Environment(\.keyWorkoutTypes) private var keyWorkoutTypes
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.dismiss) private var dismiss
    @Environment(\.syncEngine) private var syncEngine

    @State private var loadState: LoadState = .loading
    @State private var selection = Set<String>()
    @State private var importBanner: String?
    /// HealthKit UUIDs already in the app, read when the list loads.
    @State private var alreadyImported = Set<String>()

    /// Loading lifecycle for the HealthKit fetch.
    private enum LoadState {
        case loading
        case loaded([TrainingRecord.Cardio])
        case empty
        case error(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import from Apple Health")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            commitImport()
                        } label: {
                            Label("Import \(selection.count)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(selection.isEmpty ? Color.secondary : Color.green)
                        }
                        .disabled(selection.isEmpty || !isLoaded)
                    }
                }
                .task { await load() }
        }
    }

    // MARK: - Content switch

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView("Loading workouts from Apple Health")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let workouts):
            loadedList(workouts: workouts)
        case .empty:
            ContentUnavailableView(
                "No recent workouts",
                systemImage: "heart.slash",
                description: Text("No workouts found in the last \(Int(importLookbackDays)) days. If this is unexpected, check Settings → Health → Data Access & Devices to confirm Train has read access.")
            )
        case .error(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Could not load workouts")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadedList(workouts: [TrainingRecord.Cardio]) -> some View {
        List(workouts, id: \.healthID, selection: $selection) { workout in
            let imported = alreadyImported.contains(workout.healthID)
            ImportHealthKitRow(workout: workout, isImported: imported, useMetricUnits: useMetricUnits)
                .tag(workout.healthID)
                .selectionDisabled(imported)
        }
        .environment(\.editMode, .constant(.active))
        .overlay(alignment: .bottom) {
            if let banner = importBanner {
                Text(banner)
                    .font(.footnote)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var isLoaded: Bool {
        if case .loaded = loadState { return true }
        return false
    }

    // MARK: - Actions

    /// Requests authorization and fetches the most recent workouts.
    private func load() async {
        loadState = .loading
        do {
            let target = AppleHealthTarget(service: service)
            let since = Date().addingTimeInterval(-importLookbackDays * 86400)
            let records = try await target.fetchImports(
                since: since,
                defaults: ImportDefaults(trainingExcludedTypes: trainingExcludedTypes, keyWorkoutTypes: keyWorkoutTypes)
            )
            let workouts = records.compactMap { record -> TrainingRecord.Cardio? in
                if case .cardio(let cardio) = record { return cardio }
                return nil
            }
            alreadyImported = TrainingImporter.knownIDs(in: modelContext)
            loadState = workouts.isEmpty ? .empty : .loaded(workouts)
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// Imports the selected workouts through `TrainingImporter`, which skips
    /// anything already present and logs the batch for Undo.
    private func commitImport() {
        guard case .loaded(let workouts) = loadState else { return }
        let selected = workouts.filter { selection.contains($0.healthID) }
        let outcome: TrainingImporter.Outcome
        do {
            outcome = try TrainingImporter.importRecords(selected.map(TrainingRecord.cardio), from: .appleHealth, into: modelContext)
        } catch {
            importBanner = "Import failed: \(error.localizedDescription)"
            return
        }
        if outcome.added == 0 {
            // Everything was already imported — report and stay on screen.
            importBanner = "All selected workouts were already imported."
            return
        }
        // A batch syncs once, straight away, rather than after the debounce.
        Task { await syncEngine.syncNow() }
        dismiss()
    }
}

private extension TrainingRecord.Cardio {
    /// The HealthKit UUID every Health record carries as its anchor.
    var healthID: String { externalID ?? "" }
}

/// Single row in the HealthKit import list.
private struct ImportHealthKitRow: View {
    let workout: TrainingRecord.Cardio
    /// Already in the app: shown dimmed with an "Imported" label.
    let isImported: Bool
    let useMetricUnits: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        let exerciseType = workout.type
        HStack(spacing: 12) {
            Image(systemName: exerciseType.systemImage)
                .font(.title2)
                .foregroundStyle(exerciseType.color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseType.rawValue)
                    .font(.headline)
                Text(Self.dateFormatter.string(from: workout.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(workout.durationSeconds.formattedDuration)
                    if workout.distanceMiles > 0 {
                        Text("•")
                        Text(workout.distanceMiles.formattedDistance(metric: useMetricUnits))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if isImported {
                Spacer()
                Label("Imported", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(isImported ? 0.5 : 1)
    }
}

#Preview {
    ImportHealthKitSheet()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
