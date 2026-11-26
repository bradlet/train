//
//  MuscleBalanceStrip.swift
//  Train
//
//  The board's muscle-balance glance (#18, roadmap A2): a slim row of the
//  five regions, lit when the week's active plan covers them and dimmed
//  when it doesn't. Coverage comes from `MuscleBalance`. Plus a transient
//  notice used for copy confirmations.
//

import SwiftUI

/// Which regions the week's plan covers, at a glance.
struct MuscleBalanceStrip: View {
    let covered: Set<BodyRegion>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BodyRegion.allCases) { region in
                let isCovered = covered.contains(region)
                Label(region.rawValue, systemImage: isCovered ? "checkmark" : region.systemImage)
                    .labelStyle(.titleOnly)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(isCovered ? Color.green.opacity(0.18) : Color.clear)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isCovered ? Color.green.opacity(0.5) : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: isCovered ? [] : [3, 3])
                        )
                    )
                    .foregroundStyle(isCovered ? Color.green : Color.secondary)
                    .accessibilityLabel("\(region.rawValue): \(isCovered ? "planned" : "missing")")
                    .accessibilityIdentifier("strength.balance.\(region.rawValue)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

extension View {
    /// Shows a short message at the bottom for a few seconds.
    /// - Parameter message: The message; set to `nil` when it goes away.
    func transientNotice(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("transientNotice")
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(3))
                        if message.wrappedValue == text { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: message.wrappedValue)
    }
}
