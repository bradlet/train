//
//  ConnectionAlert.swift
//  Train
//
//  The one Home banner a broken connection gets (#23): never a modal, and
//  dismissible. A dismissal holds until the same target fails for a different
//  reason. Pure, so the choice of banner is unit-testable.
//

import Foundation

/// A connection that needs the athlete, as shown on Home.
struct ConnectionAlert: Equatable, Sendable {
    let id: ConnectionID
    let reason: String
    let action: ConnectionAttention

    /// Identifies this alert for dismissal: target plus reason.
    var key: String { "\(id.rawValue)|\(reason)" }

    /// The banner's line, e.g. "Google Sheets sync paused: Signed out on this device".
    var message: String { "\(id.displayName) sync paused: \(reason)" }

    /// The fix button's title.
    var actionTitle: String {
        switch action {
        case .signIn: return "Sign In"
        case .retry: return "Retry"
        case .chooseFolder: return "Choose Folder"
        }
    }

    /// The first target needing attention that hasn't been dismissed.
    /// - Parameters:
    ///   - statuses: Each auto-export target's identity and status, in
    ///     display order.
    ///   - dismissedKey: The key of the alert the athlete last dismissed.
    static func current(_ statuses: [(id: ConnectionID, status: ConnectionStatus)], dismissedKey: String) -> ConnectionAlert? {
        for entry in statuses {
            guard case .needsAttention(let reason, let action) = entry.status else { continue }
            let alert = ConnectionAlert(id: entry.id, reason: reason, action: action)
            if alert.key != dismissedKey { return alert }
        }
        return nil
    }
}
