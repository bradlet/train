//
//  SettingsToolbarButton.swift
//  Train
//
//  The gear that opens Settings, present on every tab. It also carries the
//  Google Sheets sync status dot, since sync controls live in Settings.
//

import SwiftUI

/// What the gear's status dot shows.
enum SettingsBadge: Equatable {
    /// A sync is queued or in flight.
    case syncing
    /// The last sync failed or needs sign-in.
    case attention

    /// The badge for a Sheets sync status, or `nil` when nothing needs
    /// showing.
    /// - Parameters:
    ///   - status: The coordinator's current status.
    ///   - isEnabled: Whether Sheets sync is turned on.
    static func forSheetsSync(_ status: GoogleSheetsSyncStatus, isEnabled: Bool) -> SettingsBadge? {
        guard isEnabled else { return nil }
        switch status {
        case .syncing: return .syncing
        case .failed, .needsAuth: return .attention
        default: return nil
        }
    }

    /// Dot colour: yellow while syncing, red when it needs attention.
    var color: Color {
        switch self {
        case .syncing: return .yellow
        case .attention: return .red
        }
    }
}

/// Adds the Settings gear to the leading edge of a navigation bar and
/// presents `SettingsView` from it.
private struct SettingsToolbarModifier: ViewModifier {
    @Environment(\.googleSheetsSync) private var sheetsSync
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gearshape")
                            if let badge = SettingsBadge.forSheetsSync(sheetsSync.status, isEnabled: sheetsSync.isEnabled) {
                                Circle()
                                    .fill(badge.color)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 4, y: -3)
                            }
                        }
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsButton")
                }
            }
            .sheet(isPresented: $isPresented) {
                SettingsView()
            }
    }
}

extension View {
    /// Adds the Settings gear to this view's navigation bar. Apply inside a
    /// `NavigationStack`.
    func settingsToolbarButton() -> some View {
        modifier(SettingsToolbarModifier())
    }
}
