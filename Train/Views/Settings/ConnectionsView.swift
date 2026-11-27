//
//  ConnectionsView.swift
//  Train
//
//  Settings → Connections (#23): one card per connection (Google Sheets, CSV,
//  Apple Health, Garmin) with its status and actions, then the import history
//  with Undo. Replaces the interim Settings → Data section. Sync runs through
//  `SyncEngine`, and every import through `TrainingImporter`.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The Connections dashboard.
struct ConnectionsView: View {
    /// The import log, newest first. Pushed views own their query so they
    /// stay live wherever they're shown from (Settings, the Home banner).
    @Query(sort: \ImportBatch.date, order: .reverse) private var importBatches: [ImportBatch]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.googleSheets) private var googleSheets
    @Environment(\.csvAutoExport) private var csvAutoExport
    @Environment(\.syncEngine) private var syncEngine
    @Environment(\.openURL) private var openURL

    // MARK: CSV state

    @State private var exportDocument: TrainingExportDocument?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var isPreImportSheetPresented = false
    @State private var isFolderPickerPresented = false
    @State private var pendingImport: PendingImport?
    @State private var importUnit: WorkoutCSVDistanceUnit = .miles
    @State private var errorMessage: String?
    @State private var undoCandidate: ImportBatch?

    // MARK: Health state

    @State private var isHealthKitImporterPresented = false

    // MARK: Garmin state

    @State private var isFITPickerPresented = false
    @State private var fitImport: FITImportRequest?

    // MARK: Sheets state

    @State private var isSheetsSyncConfirmationPresented = false
    /// When non-nil, presents the failure-explanation alert with the given
    /// reason and a Retry/Cancel pair.
    @State private var pendingFailureRetry: String?

    /// How many log entries to list.
    private static let historyLimit = 10

    var body: some View {
        List {
            sheetsSection
            csvSection
            healthSection
            garminSection
            historySection
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .folder,
            defaultFilename: TrainingCSVBundle.folderName(on: Date())
        ) { result in
            if case .failure(let error) = result {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isPreImportSheetPresented) {
            CSVImportGatewaySheet(
                onChooseFile: {
                    isPreImportSheetPresented = false
                    // Let the sheet finish dismissing before the picker shows.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isImporterPresented = true
                    }
                },
                onCancel: { isPreImportSheetPresented = false }
            )
        }
        .sheet(item: $pendingImport) { pending in
            ImportCSVConfirmationSheet(
                parsed: pending.parsed,
                duplicateCount: pending.duplicateCount,
                unit: $importUnit,
                onCancel: { pendingImport = nil },
                onConfirm: { commitImport(pending.parsed) }
            )
        }
        .sheet(isPresented: $isHealthKitImporterPresented) {
            ImportHealthKitSheet()
        }
        .confirmationDialog(
            "Undo this import?",
            isPresented: Binding(get: { undoCandidate != nil }, set: { if !$0 { undoCandidate = nil } }),
            titleVisibility: .visible,
            presenting: undoCandidate
        ) { batch in
            Button("Remove \(batch.addedCount) imported", role: .destructive) { undo(batch) }
            Button("Cancel", role: .cancel) {}
        } message: { batch in
            Text("Removes the \(batch.summary.lowercased(with: nil)) added on \(batch.date.formatted(date: .abbreviated, time: .shortened)). Anything you logged yourself stays.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("Mirror to Google Sheets?", isPresented: $isSheetsSyncConfirmationPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Turn On") { startEnableSheetsSync() }
        } message: {
            Text(Self.sheetsOverwriteNotice)
        }
        .alert(
            "Sync failed",
            isPresented: Binding(get: { pendingFailureRetry != nil }, set: { if !$0 { pendingFailureRetry = nil } }),
            presenting: pendingFailureRetry
        ) { _ in
            Button("Cancel", role: .cancel) { pendingFailureRetry = nil }
            Button("Retry") {
                pendingFailureRetry = nil
                Task { await syncEngine.syncNow() }
            }
        } message: { reason in
            Text("Error reason: \(reason)")
        }
    }

    /// What turning Sheets sync on means, said before it happens: the sheet
    /// is a mirror that Train overwrites, never a place to edit.
    static let sheetsOverwriteNotice = "Train creates a new Google Sheet with a Cardio tab and a Strength tab, and overwrites both after every change. Sync is one-way: anything you type into the sheet is replaced on the next sync. You can turn it off any time."

    // MARK: - Google Sheets

    /// Status, open, and the on/off/fix actions.
    private var sheetsSection: some View {
        Section {
            ConnectionHeaderRow(id: .googleSheets, status: googleSheets.status, detail: googleSheets.isConnected ? "Cardio + Strength tabs · Auto" : "Mirror your training to a sheet")
            if googleSheets.isConnected {
                if let spreadsheetID = googleSheets.spreadsheetID,
                   let url = URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)") {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open Sheet", systemImage: "arrow.up.right.square")
                    }
                }
                attentionButton(googleSheets.status, retry: { pendingFailureRetry = $0 }, fix: { Task { await reauthorizeSheetsSync() } })
                Button(role: .destructive) {
                    googleSheets.disconnect()
                } label: {
                    Label("Turn Off Google Sheets Sync", systemImage: "tablecells.badge.ellipsis")
                }
                .accessibilityIdentifier("settings.disableSheetsSync")
            } else {
                Button {
                    isSheetsSyncConfirmationPresented = true
                } label: {
                    Label("Mirror to Google Sheets", systemImage: "tablecells")
                }
                .accessibilityIdentifier("settings.enableSheetsSync")
            }
        } footer: {
            Text("A one-way, read-only mirror of your cardio and strength. Train overwrites the sheet on every change, so edits made in it don't last.")
        }
    }

    // MARK: - CSV

    /// Manual export/import and the auto-export folder.
    private var csvSection: some View {
        Section {
            ConnectionHeaderRow(
                id: .csvFile,
                status: csvAutoExport.status,
                detail: csvAutoExport.folderName.map { "Auto-export to “\($0)”" } ?? "Export and import any time"
            )
            Button {
                startExport()
            } label: {
                Label("Export Training (CSV)", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("settings.exportWorkouts")
            Button {
                isPreImportSheetPresented = true
            } label: {
                Label("Import Training (CSV)", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("settings.importWorkouts")
            if csvAutoExport.isConnected {
                attentionButton(csvAutoExport.status, retry: { pendingFailureRetry = $0 }, fix: { isFolderPickerPresented = true })
                Button(role: .destructive) {
                    csvAutoExport.disconnect()
                } label: {
                    Label("Turn Off Auto-Export", systemImage: "folder.badge.minus")
                }
                .accessibilityIdentifier("connections.csvAutoExport.off")
            } else {
                Button {
                    isFolderPickerPresented = true
                } label: {
                    Label("Keep a CSV Copy in a Folder…", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("connections.csvAutoExport.setUp")
            }
        } footer: {
            Text("Export writes a cardio and a strength file. Auto-export keeps train-cardio.csv and train-strength.csv up to date in a folder you choose, such as iCloud Drive. Import skips anything already in Train.")
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true
        ) { result in
            handleFileImporterResult(result)
        }
        .background(
            // A second `.fileImporter` on the same view would replace the
            // first, so the folder picker hangs off its own node.
            Color.clear.fileImporter(isPresented: $isFolderPickerPresented, allowedContentTypes: [.folder]) { result in
                handleFolderResult(result)
            }
        )
    }

    // MARK: - Apple Health

    /// Last import and the manual import action.
    private var healthSection: some View {
        let last = importBatches.first { $0.source == .appleHealth }
        return Section {
            ConnectionHeaderRow(
                id: .appleHealth,
                status: nil,
                detail: last.map { "Last import \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "No imports yet"
            )
            Button {
                isHealthKitImporterPresented = true
            } label: {
                Label("Import from Apple Health", systemImage: "heart.text.square")
            }
            .accessibilityIdentifier("settings.importHealth")
        } footer: {
            Text("Pick recent workouts to bring in. Ones already in Train are marked and skipped.")
        }
    }

    // MARK: - Garmin

    /// FIT file import (#22), plus the zero-effort Apple Health route.
    private var garminSection: some View {
        let last = importBatches.first { $0.source == .garmin }
        return Section {
            ConnectionHeaderRow(
                id: .garmin,
                status: nil,
                detail: last.map { "Last import \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "FIT files, or via Apple Health"
            )
            Button {
                isFITPickerPresented = true
            } label: {
                Label("Import FIT Files…", systemImage: "square.and.arrow.down.on.square")
            }
            .accessibilityIdentifier("connections.garmin.importFIT")
            DisclosureGroup("Other ways to bring in Garmin activities") {
                Text("**Share a FIT file:** in Garmin Connect on the web, open an activity, choose ⚙︎ → **Export Original**, then open the file with Train.")
                Text("**Through Apple Health:** in the Garmin Connect app, open **More → Settings → Connected Apps → Apple Health** and turn on **Workouts**, then use **Import from Apple Health** here.")
            }
            .font(.subheadline)
            .accessibilityIdentifier("connections.garmin.how")
        } footer: {
            Text("Activities already in Train are marked and skipped. Strength sessions stay out: log lifts in Strength.")
        }
        .background(
            Color.clear.fileImporter(
                isPresented: $isFITPickerPresented,
                allowedContentTypes: [GarminFITTarget.fitType],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .failure(let error):
                    errorMessage = "Couldn't open the files: \(error.localizedDescription)"
                case .success(let urls):
                    fitImport = FITImportRequest.reading(urls).request
                }
            }
        )
        .sheet(item: $fitImport) { request in
            ImportFITSheet(request: request)
        }
    }

    // MARK: - Import history

    /// Recent imports; any can be undone.
    @ViewBuilder
    private var historySection: some View {
        if !importBatches.isEmpty {
            Section("Import History") {
                ForEach(importBatches.prefix(Self.historyLimit)) { batch in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(batch.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                            Text(batch.summary + (batch.duplicateCount > 0 ? " · \(batch.duplicateCount) skipped" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Undo", role: .destructive) { undoCandidate = batch }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("settings.undoImport")
                    }
                }
            }
        }
    }

    // MARK: - Shared rows

    /// Retry or fix buttons for a target that needs attention.
    @ViewBuilder
    private func attentionButton(_ status: ConnectionStatus, retry: @escaping (String) -> Void, fix: @escaping () -> Void) -> some View {
        if case .needsAttention(let reason, let action) = status {
            switch action {
            case .retry:
                Button {
                    retry(reason)
                } label: {
                    Label("Retry Sync", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
            case .signIn:
                Button(action: fix) {
                    Label("Sign in to Resume Sync", systemImage: "person.crop.circle.badge.questionmark")
                }
            case .chooseFolder:
                Button(action: fix) {
                    Label("Choose the Folder Again", systemImage: "folder.badge.questionmark")
                }
            }
        }
    }

    // MARK: - Actions

    /// Signs in, creates the sheet and runs the first sync.
    private func startEnableSheetsSync() {
        Task {
            do {
                try await syncEngine.connect(googleSheets)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Re-presents sign-in, then syncs to the existing sheet.
    private func reauthorizeSheetsSync() async {
        do {
            try await googleSheets.reauthorize()
            await syncEngine.syncNow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Remembers the picked folder and writes the first copy.
    private func handleFolderResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "Couldn't use that folder: \(error.localizedDescription)"
        case .success(let url):
            csvAutoExport.choose(folder: url)
            Task {
                do {
                    try await syncEngine.connect(csvAutoExport)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Reads the snapshot and presents the folder exporter.
    private func startExport() {
        do {
            let snapshot = try TrainingSnapshot.load(from: modelContext)
            exportDocument = TrainingExportDocument(files: TrainingCSVBundle.files(for: snapshot, on: Date()))
            isExporterPresented = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Reads every picked file, parses each by its header, and presents the
    /// confirmation sheet (or an error when nothing could be read).
    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
        case .success(let urls):
            var files: [TrainingCSVBundle.File] = []
            var unreadable: [String] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    files.append(.init(name: url.lastPathComponent, text: text))
                } else {
                    unreadable.append("Could not read \(url.lastPathComponent).")
                }
            }
            var parsed = TrainingCSVBundle.parse(files)
            parsed.failures += unreadable
            guard !parsed.isEmpty || parsed.skippedCount > 0 else {
                errorMessage = parsed.failures.isEmpty ? "No training found in the selected files." : parsed.failures.joined(separator: "\n")
                return
            }
            importUnit = useMetricUnits ? .kilometers : .miles
            pendingImport = PendingImport(
                parsed: parsed,
                duplicateCount: parsed.duplicateCount(known: TrainingImporter.knownIDs(in: modelContext))
            )
        }
    }

    /// Imports the parsed rows through `TrainingImporter`, then syncs once.
    private func commitImport(_ parsed: TrainingCSVBundle.Parsed) {
        do {
            let outcome = try TrainingImporter.importRecords(parsed.records(cardioUnit: importUnit), from: .csvFile, into: modelContext)
            if outcome.added > 0 {
                Task { await syncEngine.syncNow() }
            }
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
        pendingImport = nil
    }

    /// Removes an import, then syncs the mirrors.
    private func undo(_ batch: ImportBatch) {
        do {
            try TrainingImporter.undo(batch, in: modelContext)
            Task { await syncEngine.syncNow() }
        } catch {
            errorMessage = "Undo failed: \(error.localizedDescription)"
        }
    }
}

/// A connection's icon, name, one-line detail and status.
private struct ConnectionHeaderRow: View {
    let id: ConnectionID
    /// `nil` for import-only sources, which have no live status.
    let status: ConnectionStatus?
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: id.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(id.displayName)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let status {
                ConnectionStatusLabel(status: status)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connections.\(id.rawValue)")
    }
}

/// A dot and a word for a connection's status.
struct ConnectionStatusLabel: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var text: String {
        switch status {
        case .disconnected: return "Off"
        case .syncing: return "Syncing…"
        case .connected(let lastSync):
            guard let lastSync else { return "On" }
            return "Synced \(lastSync.formatted(.relative(presentation: .named)))"
        case .needsAttention: return "Paused"
        }
    }

    private var color: Color {
        switch status {
        case .disconnected: return .gray
        case .syncing: return .yellow
        case .connected: return .green
        case .needsAttention: return .red
        }
    }
}

/// Parsed files waiting for the athlete to confirm.
private struct PendingImport: Identifiable {
    let id = UUID()
    let parsed: TrainingCSVBundle.Parsed
    let duplicateCount: Int
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

                Text("Select one or more CSV files to import: a cardio file, a strength file, or both.")
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
            .navigationTitle("Import Training")
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
