//
//  ImportFITSheet.swift
//  Train
//
//  Review and import Garmin FIT activities (#22), whether picked in
//  Connections or shared into the app. Every new workout starts ticked;
//  ones already in Train (by FIT anchor) are shown as imported and can't be
//  picked. The commit goes through `TrainingImporter`, so it lands in the
//  import log with Undo.
//

import SwiftUI
import SwiftData

/// FIT files waiting to be reviewed.
struct FITImportRequest: Identifiable {
    let id = UUID()
    /// Each file's name and bytes.
    let files: [(name: String, data: Data)]

    /// Reads files from URLs, with security-scoped access where needed.
    /// - Parameter urls: Picked or shared file URLs.
    /// - Returns: The request, plus the names of files that couldn't be read.
    static func reading(_ urls: [URL]) -> (request: FITImportRequest, unreadable: [String]) {
        var files: [(name: String, data: Data)] = []
        var unreadable: [String] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                files.append((url.lastPathComponent, data))
            } else {
                unreadable.append(url.lastPathComponent)
            }
        }
        return (FITImportRequest(files: files), unreadable)
    }
}

/// Lists a FIT import's workouts for the athlete to confirm.
struct ImportFITSheet: View {
    let request: FITImportRequest

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.trainingExcludedTypes) private var trainingExcludedTypes
    @Environment(\.keyWorkoutTypes) private var keyWorkoutTypes
    @Environment(\.syncEngine) private var syncEngine

    @State private var parsed = GarminFITTarget.Parsed()
    @State private var known = Set<String>()
    @State private var selection = Set<String>()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    ForEach(parsed.records, id: \.anchor) { record in
                        let imported = known.contains(record.anchor)
                        FITWorkoutRow(record: record, isImported: imported, useMetricUnits: useMetricUnits)
                            .tag(record.anchor)
                            .selectionDisabled(imported)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if parsed.skippedStrength > 0 {
                            Text("\(parsed.skippedStrength) strength session\(parsed.skippedStrength == 1 ? "" : "s") left out: log lifts in Strength, where each lift keeps its own number.")
                        }
                        ForEach(parsed.failures, id: \.self) { Text($0) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .overlay {
                if parsed.records.isEmpty {
                    ContentUnavailableView(
                        "No workouts found",
                        systemImage: "applewatch.slash",
                        description: Text(parsed.failures.first ?? "These files have no cardio activities to import.")
                    )
                }
            }
            .navigationTitle("Import from Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selection.count)") { commit() }
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("importFIT.confirm")
                }
            }
            .alert("Import failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .task { load() }
        }
    }

    /// Parses the files and ticks every workout not already in Train.
    private func load() {
        parsed = GarminFITTarget.parse(
            request.files,
            defaults: ImportDefaults(trainingExcludedTypes: trainingExcludedTypes, keyWorkoutTypes: keyWorkoutTypes)
        )
        known = TrainingImporter.knownIDs(in: modelContext)
        selection = Set(parsed.records.map(\.anchor).filter { !known.contains($0) })
    }

    /// Imports the ticked workouts, then syncs once.
    private func commit() {
        let chosen = parsed.records.filter { selection.contains($0.anchor) }
        do {
            let outcome = try TrainingImporter.importRecords(chosen.map(TrainingRecord.cardio), from: .garmin, into: modelContext)
            if outcome.added > 0 { Task { await syncEngine.syncNow() } }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension TrainingRecord.Cardio {
    /// The FIT anchor every Garmin record carries.
    var anchor: String { externalID ?? "" }
}

/// One FIT workout row.
private struct FITWorkoutRow: View {
    let record: TrainingRecord.Cardio
    let isImported: Bool
    let useMetricUnits: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.type.systemImage)
                .font(.title2)
                .foregroundStyle(record.type.color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.type.rawValue).font(.headline)
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(record.durationSeconds.formattedDuration)
                    if record.distanceMiles > 0 {
                        Text("•")
                        Text(record.distanceMiles.formattedDistance(metric: useMetricUnits))
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
        .opacity(isImported ? 0.5 : 1)
    }
}
