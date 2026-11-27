//
//  ConnectionsEnvironment.swift
//  Train
//
//  Environment keys for the connections layer (#21): the app's `SyncEngine`
//  and its Google Sheets target. Defaults are stub-backed so previews and
//  tests never trigger real OAuth or hit the network; the app root injects
//  the live pair.
//

import SwiftUI

/// Environment key for the shared Google Sheets target.
private struct GoogleSheetsKey: EnvironmentKey {
    @MainActor
    static let defaultValue = GoogleSheetsTarget(api: StubGoogleSheetsAPI(isAuthorized: false))
}

/// Environment key for the shared sync engine.
private struct SyncEngineKey: EnvironmentKey {
    @MainActor
    static let defaultValue = SyncEngine(targets: [GoogleSheetsKey.defaultValue])
}

extension EnvironmentValues {
    /// The Google Sheets target (sign-in, status, on/off). Defaults to a
    /// stub-backed instance.
    var googleSheets: GoogleSheetsTarget {
        get { self[GoogleSheetsKey.self] }
        set { self[GoogleSheetsKey.self] = newValue }
    }

    /// The engine that keeps every auto-export target current. Defaults to
    /// a stub-backed instance.
    var syncEngine: SyncEngine {
        get { self[SyncEngineKey.self] }
        set { self[SyncEngineKey.self] = newValue }
    }
}
