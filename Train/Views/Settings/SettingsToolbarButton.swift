//
//  SettingsToolbarButton.swift
//  Train
//
//  The gear that opens Settings, present on every tab. It also carries the
//  connections status dot (#21), since sync controls live in Settings.
//

import SwiftUI

/// What the gear's status dot shows.
enum SettingsBadge: Equatable {
    /// A sync is queued or in flight.
    case syncing
    /// The last sync failed or needs sign-in.
    case attention

    /// The badge for the connections' statuses, or `nil` when nothing
    /// needs showing. Attention outranks syncing.
    /// - Parameter statuses: Every auto-export target's status.
    static func forConnections(_ statuses: [ConnectionStatus]) -> SettingsBadge? {
        if statuses.contains(where: \.needsAttention) { return .attention }
        if statuses.contains(where: \.isSyncing) { return .syncing }
        return nil
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
    @Environment(\.syncEngine) private var syncEngine
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
                            if let badge = SettingsBadge.forConnections(syncEngine.targets.map(\.status)) {
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
