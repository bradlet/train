//
//  PlanRouter.swift
//  Train
//
//  Cross-tab navigation into a Plan for a given day (#19): a tap on the Home
//  week strip's run cell opens Cardio → Plan on that week, a lift cell opens
//  Strength → Plan on that weekday. App-scope observable state (not a
//  ViewModel), injected through the environment like `CoachLaunchRouter`.
//

import SwiftUI

/// Selects a tab and hands a target day to the Plan it opens.
@MainActor
@Observable
final class PlanRouter {
    /// The selected tab.
    var tab: AppTab = .home
    /// A day for Cardio → Plan to show, consumed once it has.
    var cardioDay: Date?
    /// A weekday for Strength → Plan to show, consumed once it has.
    var strengthWeekday: Int?

    /// Opens Cardio → Plan on the week containing `day`.
    func openCardio(on day: Date) {
        cardioDay = day
        tab = .cardio
    }

    /// Opens Strength → Plan on `weekday` (Sunday=0 ... Saturday=6).
    func openStrength(on weekday: Int) {
        strengthWeekday = weekday
        tab = .strength
    }
}

private struct PlanRouterKey: EnvironmentKey {
    @MainActor static let defaultValue = PlanRouter()
}

extension EnvironmentValues {
    /// The app's plan router.
    var planRouter: PlanRouter {
        get { self[PlanRouterKey.self] }
        set { self[PlanRouterKey.self] = newValue }
    }
}
