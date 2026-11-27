//
//  ConnectionTarget.swift
//  Train
//
//  The vocabulary every import/export target shares (#21): its identity,
//  what it can do, and one status model the UI reads the same way for all of
//  them. Two refinements carry the work:
//
//  - `AutoExportTarget` mirrors the app's training out on every change
//    (Google Sheets today; CSV auto-export joins in #23). `SyncEngine` drives
//    these: debounce, status, retry.
//  - `ImportSourceTarget` fetches records in (Apple Health; Garmin in #22).
//    Imports are always the athlete's action and always go through
//    `TrainingImporter`, so a source's "last import" is read from the
//    import log rather than kept as live status.
//

import Foundation
import SwiftData

/// Every connection the app knows about.
enum ConnectionID: String, CaseIterable, Codable, Sendable {
    case googleSheets
    case csvFile
    case appleHealth
    case garmin

    /// Display name.
    var displayName: String {
        switch self {
        case .googleSheets: return "Google Sheets"
        case .csvFile: return "CSV"
        case .appleHealth: return "Apple Health"
        case .garmin: return "Garmin"
        }
    }

    /// SF Symbol for the connection.
    var systemImage: String {
        switch self {
        case .googleSheets: return "tablecells"
        case .csvFile: return "doc.text"
        case .appleHealth: return "heart.text.square"
        case .garmin: return "applewatch"
        }
    }
}

/// What a target can do.
struct ConnectionCapabilities: OptionSet, Sendable {
    let rawValue: Int

    /// Brings records into the app.
    static let `import` = ConnectionCapabilities(rawValue: 1 << 0)
    /// Writes the app's records out on request.
    static let export = ConnectionCapabilities(rawValue: 1 << 1)
    /// Keeps an exported copy up to date on every change.
    static let autoExport = ConnectionCapabilities(rawValue: 1 << 2)
}

/// What fixes a target that needs attention.
enum ConnectionAttention: Equatable, Sendable {
    /// The sign-in expired or was revoked; retrying won't help.
    case signIn
    /// A transient failure; trying again may.
    case retry
    /// A chosen folder can no longer be reached; pick it again.
    case chooseFolder
}

/// A target's state, read the same way for every target.
enum ConnectionStatus: Equatable, Sendable {
    /// Not set up.
    case disconnected
    /// Set up and healthy; `lastSync` is `nil` until the first sync this
    /// session.
    case connected(lastSync: Date?)
    /// An export is queued or in flight.
    case syncing
    /// Paused until the athlete acts.
    case needsAttention(reason: String, action: ConnectionAttention)

    /// Whether the athlete has to act.
    var needsAttention: Bool {
        if case .needsAttention = self { return true }
        return false
    }

    /// Whether an export is queued or in flight.
    var isSyncing: Bool { self == .syncing }
}

/// Defaults an import applies to records whose source says nothing about
/// them: the athlete's training inclusion and key-workout choices.
struct ImportDefaults: Equatable, Sendable {
    /// Types that don't count toward training (#17).
    var trainingExcludedTypes: Set<ExerciseType> = TrainingInclusion.defaultExcluded
    /// Types the athlete marks key by default (#25).
    var keyWorkoutTypes: Set<ExerciseType> = []
}

/// A connection the app can show and talk to.
@MainActor
protocol ConnectionTarget: AnyObject {
    /// Which connection this is.
    var id: ConnectionID { get }
    /// What it can do.
    var capabilities: ConnectionCapabilities { get }
}

extension ConnectionTarget {
    /// Display name.
    var displayName: String { id.displayName }
}

/// A target that mirrors the app's training out and is kept current by
/// `SyncEngine`. Implementations own their own sign-in and persisted state;
/// the engine owns when to export and the status around it.
@MainActor
protocol AutoExportTarget: ConnectionTarget {
    /// Current state. The engine writes it around each export.
    var status: ConnectionStatus { get set }
    /// Whether the athlete has set this target up.
    var isConnected: Bool { get }

    /// Restores persisted state at launch and sets the initial status.
    /// Never presents UI.
    func restore(from container: ModelContainer) async
    /// Sets the target up; may present UI. Throws on cancel or failure.
    func connect() async throws
    /// Stops exporting and forgets this device's credentials. Data already
    /// exported is left where it is.
    func disconnect()
    /// A status to show *instead* of exporting, e.g. signed out on this
    /// device, or `nil` when ready.
    func readinessProblem() -> ConnectionStatus?
    /// Writes the snapshot out, replacing the previous copy.
    func export(_ snapshot: TrainingSnapshot) async throws
    /// The status an export failure leaves behind.
    func status(afterFailure error: Error) -> ConnectionStatus
}

/// A target that brings records in.
@MainActor
protocol ImportSourceTarget: ConnectionTarget {
    /// Fetches recent activity as interchange records, newest first.
    /// May present a permission prompt.
    /// - Parameters:
    ///   - since: Inclusive lower bound on the activity date.
    ///   - defaults: Inclusion and key defaults for what the source lacks.
    func fetchImports(since: Date, defaults: ImportDefaults) async throws -> [TrainingRecord]
}
