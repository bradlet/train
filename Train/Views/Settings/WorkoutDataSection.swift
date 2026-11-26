//
//  WorkoutDataSection.swift
//  Train
//
//  Settings → Data: CSV export and import, Apple Health import, and Google
//  Sheets sync. Moved here from the old History tab's toolbar menu when
//  History became Cardio → Progress (#12); an interim home until the
//  Connections dashboard (#23).
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The Data section of Settings: every import, export and sync action.
struct WorkoutDataSection: View {
    /// Recorded exercises, most recent first — what export writes.
    let completedExercises: [Exercise]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.googleSheetsSync) private var sheetsSync

    // MARK: CSV Import/Export state

    @State private var exportDocument: WorkoutCSVDocument?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var isPreImportSheetPresented = false
    @State private var pendingImport: PendingImport?
    @State private var importUnit: WorkoutCSVDistanceUnit = .miles
    @State private var errorMessage: String?

    // MARK: HealthKit Import state

    @State private var isHealthKitImporterPresented = false

    // MARK: Google Sheets Sync state

    @State private var isSheetsSyncConfirmationPresented = false
    /// When non-nil, presents the failure-explanation alert with the given
    /// reason and a Retry/Cancel pair.
    @State private var pendingFailureRetry: String?

    var body: some View {
        Section {
            Button {
                startExport()
            } label: {
                Label("Export Workouts (CSV)", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("settings.exportWorkouts")
            Button {
                isPreImportSheetPresented = true
            } label: {
                Label("Import Workouts (CSV)", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("settings.importWorkouts")
            Button {
                isHealthKitImporterPresented = true
            } label: {
                Label("Import from Apple Health", systemImage: "heart.text.square")
            }
            .accessibilityIdentifier("settings.importHealth")
        } header: {
            Text("Data")
        } footer: {
            Text("Your training is yours: export it any time, or bring in history from elsewhere.")
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: defaultExportFilename()
        ) { result in
            if case .failure(let error) = result {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isPreImportSheetPresented) {
            CSVImportGatewaySheet(
                onChooseFile: {
                    isPreImportSheetPresented = false
                    // Delay slightly so the sheet dismissal completes
                    // before the file importer is presented.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isImporterPresented = true
                    }
                },
                onCancel: { isPreImportSheetPresented = false }
            )
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.commaSeparatedText]
        ) { result in
            handleFileImporterResult(result)
        }
        .sheet(item: $pendingImport) { pending in
            ImportCSVConfirmationSheet(
                filename: pending.filename,
                parseResult: pending.result,
                unit: $importUnit,
                onCancel: { pendingImport = nil },
                onConfirm: { commitImport(pending.result) }
            )
        }
        .sheet(isPresented: $isHealthKitImporterPresented) {
            ImportHealthKitSheet()
        }

        sheetsSyncSection
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .alert(
                "Enable Google Sheets Sync?",
                isPresented: $isSheetsSyncConfirmationPresented
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Enable") { startEnableSheetsSync() }
            } message: {
                Text("This will create a new Google Sheet and overwrite it every time you add or edit a workout. Sync is one-way: any edits you make in Google Sheets will be wiped on the next save. You can turn sync off any time in Settings.")
            }
            .alert(
                "Sync failed",
                isPresented: Binding(
                    get: { pendingFailureRetry != nil },
                    set: { if !$0 { pendingFailureRetry = nil } }
                ),
                presenting: pendingFailureRetry
            ) { _ in
                Button("Cancel", role: .cancel) { pendingFailureRetry = nil }
                Button("Retry") {
                    pendingFailureRetry = nil
                    Task { await sheetsSync.syncNow() }
                }
            } message: { reason in
                Text("Error reason: \(reason)")
            }
    }

    // MARK: Google Sheets Sync

    /// Google Sheets sync controls. Adapts to the coordinator state: not
    /// enabled → enable; failed → retry + turn off; needs auth → sign in +
    /// turn off; enabled and healthy → status + turn off.
    private var sheetsSyncSection: some View {
        Section {
            if sheetsSync.isEnabled {
                sheetsSyncStatusRow
                switch sheetsSync.status {
                case .failed(let reason):
                    Button {
                        pendingFailureRetry = reason
                    } label: {
                        Label("Retry Sync", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    }
                case .needsAuth:
                    Button {
                        Task { await reauthorizeSheetsSync() }
                    } label: {
                        Label("Sign in to Resume Sync", systemImage: "person.crop.circle.badge.questionmark")
                    }
                default:
                    EmptyView()
                }
                Button(role: .destructive) {
                    sheetsSync.disable()
                } label: {
                    Label("Turn Off Google Sheets Sync", systemImage: "tablecells.badge.ellipsis")
                }
                .accessibilityIdentifier("settings.disableSheetsSync")
            } else {
                Button {
                    isSheetsSyncConfirmationPresented = true
                } label: {
                    Label("Sync to Google Sheets", systemImage: "tablecells")
                }
                .accessibilityIdentifier("settings.enableSheetsSync")
            }
        } header: {
            Text("Google Sheets")
        } footer: {
            Text("Keeps a one-way copy of your recorded workouts in a Google Sheet.")
        }
    }

    /// Non-actionable status row: syncing, synced, failed or signed out.
    @ViewBuilder
    private var sheetsSyncStatusRow: some View {
        switch sheetsSync.status {
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .success, .idle:
            Label("Synced", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Last sync failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .needsAuth:
            Label("Signed out on this device", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.orange)
        }
    }

    /// Kicks off the OAuth + sheet creation + initial sync flow. Failures
    /// surface via the shared `errorMessage` alert.
    private func startEnableSheetsSync() {
        Task {
            do {
                try await sheetsSync.enable()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Re-presents OAuth on a device where sync is enabled in
    /// AppConfiguration but no token exists locally. Reuses the existing
    /// spreadsheet ID rather than creating a new one.
    private func reauthorizeSheetsSync() async {
        do {
            try await sheetsSync.reauthorize()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Export

    /// Builds the CSV document from the recorded workouts and triggers the
    /// exporter.
    private func startExport() {
        let unit: WorkoutCSVDistanceUnit = useMetricUnits ? .kilometers : .miles
        let csv = WorkoutCSV.encode(exercises: completedExercises, unit: unit)
        exportDocument = WorkoutCSVDocument(text: csv)
        isExporterPresented = true
    }

    /// Produces a dated default filename like `workouts-2026-04-09.csv`.
    private func defaultExportFilename() -> String {
        "workouts-\(Self.filenameDateFormatter.string(from: Date()))"
    }

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: Import

    /// Handles the result from `.fileImporter`: reads the picked URL,
    /// parses it, and either presents the confirmation sheet or an error.
    private func handleFileImporterResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let parsed = try WorkoutCSV.parse(text)
                importUnit = useMetricUnits ? .kilometers : .miles
                pendingImport = PendingImport(
                    filename: url.lastPathComponent,
                    result: parsed
                )
            } catch WorkoutCSVError.empty {
                errorMessage = "This file is empty."
            } catch WorkoutCSVError.missingHeader {
                errorMessage = "This file is missing a header row."
            } catch {
                errorMessage = "Could not read file: \(error.localizedDescription)"
            }
        }
    }

    /// Inserts all successfully parsed rows as new completed exercises.
    private func commitImport(_ result: WorkoutCSVParseResult) {
        for row in result.rows {
            let exercise = WorkoutCSV.toExercise(row, unit: importUnit)
            modelContext.insert(exercise)
        }
        do {
            try modelContext.save()
            // Batch imports skip the per-mutation debounce and sync once
            // after every parsed row has been inserted. Only fired on
            // successful save so a partial-failure path doesn't trigger
            // an upload of inconsistent state.
            Task { await sheetsSync.syncNow() }
        } catch {
            errorMessage = "Saved partial import: \(error.localizedDescription)"
        }
        pendingImport = nil
    }
}

/// A pending import waiting for user confirmation.
private struct PendingImport: Identifiable {
    let id = UUID()
    let filename: String
    let result: WorkoutCSVParseResult
}

/// Gateway sheet shown before opening the file picker, with a link to import help.
private struct CSVImportGatewaySheet: View {
    let onChooseFile: () -> Void
    let onCancel: () -> Void
    @State private var isHelpPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Select a CSV file to import your workout history.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Button(action: onChooseFile) {
                    Label("Choose File", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Import Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isHelpPresented = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .sheet(isPresented: $isHelpPresented) {
                CSVImportHelpView()
            }
        }
        .presentationDetents([.medium])
    }
}
