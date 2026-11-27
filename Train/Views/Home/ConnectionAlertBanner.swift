//
//  ConnectionAlertBanner.swift
//  Train
//
//  Home's banner for a connection that needs attention (#23): one line, a
//  fix button that opens Connections, and a dismiss button.
//

import SwiftUI

/// A dismissible banner for a paused connection.
struct ConnectionAlertBanner: View {
    let alert: ConnectionAlert
    /// Opens Connections to fix it.
    let onFix: () -> Void
    /// Hides it until the connection fails for another reason.
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(alert.message)
                    .font(.subheadline)
                Button(alert.actionTitle, action: onFix)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("home.connectionAlert.fix")
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("home.connectionAlert.dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("home.connectionAlert")
    }
}

#Preview {
    ConnectionAlertBanner(
        alert: ConnectionAlert(id: .googleSheets, reason: "Signed out on this device", action: .signIn),
        onFix: {}, onDismiss: {}
    )
    .padding()
}
