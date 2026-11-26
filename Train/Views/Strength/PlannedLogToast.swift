//
//  PlannedLogToast.swift
//  Train
//
//  The "Logged 4 lifts · Undo · Adjust" toast after a one-tap "as planned"
//  log (#26). Undo removes exactly the records written; Adjust swaps them
//  for the whole-day sheet, pre-ticked with the same values. The host owns
//  both actions — this file is presentation only.
//

import SwiftUI

extension View {
    /// Shows the as-planned toast at the bottom while `result` is set,
    /// clearing it after a few seconds.
    /// - Parameters:
    ///   - result: The tap being reported; `nil` hides the toast.
    ///   - onUndo: Removes the tap's records.
    ///   - onAdjust: Replaces the tap's records with the whole-day sheet.
    func plannedLogToast(
        _ result: Binding<PlannedDayLogResult?>,
        onUndo: @escaping (PlannedDayLogResult) -> Void,
        onAdjust: @escaping (PlannedDayLogResult) -> Void
    ) -> some View {
        modifier(PlannedLogToastModifier(result: result, onUndo: onUndo, onAdjust: onAdjust))
    }
}

/// Hosts the toast overlay and its auto-dismiss.
private struct PlannedLogToastModifier: ViewModifier {
    @Binding var result: PlannedDayLogResult?
    let onUndo: (PlannedDayLogResult) -> Void
    let onAdjust: (PlannedDayLogResult) -> Void

    /// Long enough to reach Undo, short enough to get out of the way.
    private static let visibleFor: Duration = .seconds(6)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let result {
                    toast(result)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: result)
            .task(id: result?.id) {
                guard result != nil else { return }
                try? await Task.sleep(for: Self.visibleFor)
                guard !Task.isCancelled else { return }
                result = nil
            }
    }

    private func toast(_ shown: PlannedDayLogResult) -> some View {
        HStack(spacing: 12) {
            Label(shown.message, systemImage: "dumbbell.fill")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("plannedLog.message")
            Spacer(minLength: 8)
            Button("Undo") {
                result = nil
                onUndo(shown)
            }
            .accessibilityIdentifier("plannedLog.undo")
            Button("Adjust") {
                result = nil
                onAdjust(shown)
            }
            .accessibilityIdentifier("plannedLog.adjust")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
