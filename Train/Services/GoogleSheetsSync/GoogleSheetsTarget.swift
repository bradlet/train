//
//  GoogleSheetsTarget.swift
//  Train
//
//  Google Sheets as an `AutoExportTarget` (#21). Owns the sign-in, the
//  spreadsheet it writes to, and the persisted on/off state; `SyncEngine`
//  decides when to export. The sheet is a one-way mirror with a Cardio tab
//  and a Strength tab, both overwritten from the app on every sync: edits
//  made in the sheet never survive, and set-up says so.
//
//  One instance lives in App scope, exposed via `@Environment(\.googleSheets)`.
//  Views never touch `GoogleSheetsAPI` directly.
//

import Foundation
import Observation
import SwiftData

/// The Google Sheets mirror of the athlete's training.
@MainActor
@Observable
final class GoogleSheetsTarget: AutoExportTarget {

    let id: ConnectionID = .googleSheets
    let capabilities: ConnectionCapabilities = [.export, .autoExport]

    /// Current state; `SyncEngine` writes it around each export.
    var status: ConnectionStatus = .disconnected

    /// Whether the athlete turned sync on. Mirrors
    /// `AppConfiguration.googleSheetsSyncEnabled`.
    private(set) var isEnabled = false

    /// The spreadsheet written to; `nil` until the first connect.
    private(set) var spreadsheetID: String?

    var isConnected: Bool { isEnabled && spreadsheetID != nil }

    /// Tab names, in order.
    static let cardioTab = "Cardio"
    static let strengthTab = "Strength"

    /// Title of a newly created spreadsheet.
    static let spreadsheetTitle = "Train"

    /// What the status shows while signed out on this device.
    static let signedOutReason = "Signed out on this device"

    @ObservationIgnored private let api: GoogleSheetsAPI
    @ObservationIgnored private weak var modelContainer: ModelContainer?
    /// The spreadsheet whose tabs were checked this session, so the check
    /// runs once rather than on every sync.
    @ObservationIgnored private var preparedSpreadsheetID: String?

    /// Creates the target.
    /// - Parameter api: The OAuth + Sheets REST layer.
    init(api: GoogleSheetsAPI) {
        self.api = api
    }

    // MARK: - AutoExportTarget

    /// Restores on/off state from `AppConfiguration` and silently restores
    /// the Google session, so the next change can sync without a prompt.
    func restore(from container: ModelContainer) async {
        modelContainer = container
        let context = ModelContext(container)
        if let config = try? context.fetch(FetchDescriptor<AppConfiguration>()).first {
            isEnabled = config.googleSheetsSyncEnabled
            spreadsheetID = config.googleSheetsSpreadsheetID.isEmpty ? nil : config.googleSheetsSpreadsheetID
        }
        guard isConnected else {
            status = .disconnected
            return
        }
        let restored = await api.restoreAuthorizationIfPossible()
        status = restored ? .connected(lastSync: nil) : .needsAttention(reason: Self.signedOutReason, action: .signIn)
    }

    /// Signs in, creates a fresh spreadsheet with both tabs, and persists
    /// the on state. `SyncEngine.connect(_:)` then runs the first export.
    func connect() async throws {
        guard let modelContainer else { throw GoogleSheetsSyncError.notAttached }
        try await api.authorize()
        let id = try await api.createSpreadsheet(title: Self.spreadsheetTitle, tabs: [Self.cardioTab, Self.strengthTab])
        persist(enabled: true, spreadsheetID: id, in: modelContainer)
        isEnabled = true
        spreadsheetID = id
        preparedSpreadsheetID = id
        status = .connected(lastSync: nil)
    }

    /// Forces a fresh interactive sign-in for the existing spreadsheet, on a
    /// device where sync is on but the session expired, was revoked, or was
    /// never made here. Call `SyncEngine.syncNow()` after it.
    func reauthorize() async throws {
        guard isConnected else { throw GoogleSheetsSyncError.notAuthorized }
        // Never trust a cached session here: a revoked grant still looks
        // valid locally until its access token expires (~1h), so a silent
        // refresh would loop straight back to "needs sign-in".
        try await api.reauthorizeInteractively()
        status = .connected(lastSync: nil)
    }

    /// Signs out and clears the persisted state. The sheet stays in the
    /// athlete's Drive.
    func disconnect() {
        api.signOut()
        if let modelContainer {
            persist(enabled: false, spreadsheetID: "", in: modelContainer)
        }
        isEnabled = false
        spreadsheetID = nil
        preparedSpreadsheetID = nil
        status = .disconnected
    }

    func readinessProblem() -> ConnectionStatus? {
        api.isAuthorized ? nil : .needsAttention(reason: Self.signedOutReason, action: .signIn)
    }

    /// Overwrites both tabs from the snapshot. A spreadsheet made before
    /// the tabs existed gets them first (its `Sheet1` becomes Cardio).
    func export(_ snapshot: TrainingSnapshot) async throws {
        guard let spreadsheetID else { throw GoogleSheetsSyncError.notAttached }
        if preparedSpreadsheetID != spreadsheetID {
            try await api.prepareTabs(spreadsheetId: spreadsheetID, tabs: [Self.cardioTab, Self.strengthTab])
            preparedSpreadsheetID = spreadsheetID
        }
        let unit: WorkoutCSVDistanceUnit = snapshot.useMetricUnits ? .kilometers : .miles
        try await api.overwriteSheet(
            spreadsheetId: spreadsheetID,
            tab: Self.cardioTab,
            rows: WorkoutCSV.rows(cardio: snapshot.cardio, unit: unit)
        )
        try await api.overwriteSheet(
            spreadsheetId: spreadsheetID,
            tab: Self.strengthTab,
            rows: StrengthCSV.rows(strength: snapshot.strength, metric: snapshot.useMetricUnits)
        )
    }

    /// An expired or revoked sign-in (`.notAuthorized`, HTTP 401/403) needs
    /// a sign-in, since a retry would fail again; anything else is retryable.
    func status(afterFailure error: Error) -> ConnectionStatus {
        Self.isAuthError(error)
            ? .needsAttention(reason: Self.signedOutReason, action: .signIn)
            : .needsAttention(reason: error.localizedDescription, action: .retry)
    }

    // MARK: - Internals

    /// Whether `error` means the Google session is no longer valid.
    static func isAuthError(_ error: Error) -> Bool {
        switch error {
        case GoogleSheetsSyncError.notAuthorized:
            return true
        case GoogleSheetsSyncError.httpError(let status, _):
            return status == 401 || status == 403
        default:
            return false
        }
    }

    /// Writes the on/off state and spreadsheet ID to `AppConfiguration`.
    private func persist(enabled: Bool, spreadsheetID: String, in container: ModelContainer) {
        let context = ModelContext(container)
        let config = AppConfiguration.current(in: context)
        config.googleSheetsSyncEnabled = enabled
        config.googleSheetsSpreadsheetID = spreadsheetID
        try? context.save()
    }
}
