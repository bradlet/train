//
//  CoachLaunchEnvironment.swift
//  Train
//
//  SwiftUI environment key that injects the shared `CoachLaunchRouter`.
//  The default value is a fresh router so previews and tests never see an
//  entry routed elsewhere; the app root injects `CoachLaunchRouter.shared`.
//

import SwiftUI

/// Environment key for the `CoachLaunchRouter` instance.
private struct CoachLaunchKey: EnvironmentKey {
    @MainActor
    static let defaultValue = CoachLaunchRouter()
}

extension EnvironmentValues {
    /// The router carrying external launches (widget, Siri) into the coach.
    var coachLauncher: CoachLaunchRouter {
        get { self[CoachLaunchKey.self] }
        set { self[CoachLaunchKey.self] = newValue }
    }
}
