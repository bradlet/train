//
//  NewBestBanner.swift
//  Train
//
//  The brief "New best" banner shown after a save beats a lift's previous
//  best for its metric and measurement (#15, W2; detection lives in
//  `StrengthPersonalBest`). The record sheets report bests through an
//  `onNewBest` callback and dismiss as usual; the presenting view (Home or
//  the board) shows the banner, so recording never waits on a celebration.
//

import SwiftUI

/// One "New best" announcement: the lifts that set a best in a single save.
struct NewBestAnnouncement: Identifiable, Equatable {
    let id = UUID()
    /// Names of the lifts that set a new best, in save order.
    let liftNames: [String]

    /// The banner text, e.g. "New best · Bench Press", "New bests · Squat,
    /// Row", or "New bests on 3 lifts" once a list would get long.
    static func message(for liftNames: [String]) -> String {
        switch liftNames.count {
        case 0: return "New best"
        case 1: return "New best · \(liftNames[0])"
        case 2: return "New bests · \(liftNames[0]), \(liftNames[1])"
        default: return "New bests on \(liftNames.count) lifts"
        }
    }

    /// This announcement's banner text.
    var message: String { Self.message(for: liftNames) }
}

extension View {
    /// Shows a transient "New best" banner at the top while `announcement`
    /// is set, with a success haptic, clearing it after a few seconds.
    /// - Parameter announcement: The announcement to show; set to `nil` when
    ///   the banner goes away.
    func newBestBanner(_ announcement: Binding<NewBestAnnouncement?>) -> some View {
        modifier(NewBestBannerModifier(announcement: announcement))
    }
}

/// Hosts the banner overlay and its auto-dismiss.
private struct NewBestBannerModifier: ViewModifier {
    @Binding var announcement: NewBestAnnouncement?

    /// How long the banner stays up.
    private static let visibleFor: Duration = .seconds(3)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let announcement {
                    Label(announcement.message, systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.orange.gradient))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { self.announcement = nil }
                        .accessibilityIdentifier("newBestBanner")
                }
            }
            .animation(.spring(duration: 0.35), value: announcement)
            .sensoryFeedback(.success, trigger: announcement?.id) { _, new in new != nil }
            .task(id: announcement?.id) {
                guard announcement != nil else { return }
                try? await Task.sleep(for: Self.visibleFor)
                guard !Task.isCancelled else { return }
                announcement = nil
            }
    }
}
