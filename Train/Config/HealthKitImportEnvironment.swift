//
//  HealthKitImportEnvironment.swift
//  Train
//
//  Custom SwiftUI environment key that injects a `HealthKitImportService`
//  into the view hierarchy. Default value is `StubHealthKitImportService`
//  so previews and tests never trigger a real HealthKit authorization
//  prompt.
//

import SwiftUI

/// Environment key for the shared `HealthKitImportService` instance.
private struct HealthKitImportKey: EnvironmentKey {
    static let defaultValue: HealthKitImportService = StubHealthKitImportService()
}

extension EnvironmentValues {
    /// The active HealthKit import service. Defaults to
    /// `StubHealthKitImportService`; the real implementation is injected
    /// at the app root.
    var healthKitImport: HealthKitImportService {
        get { self[HealthKitImportKey.self] }
        set { self[HealthKitImportKey.self] = newValue }
    }
}

/// Environment key for the new-workout watcher (#37). The default is
/// stub-backed with a throwaway suite, so previews never touch HealthKit,
/// notifications, or the app's switches.
private struct HealthWorkoutWatcherKey: EnvironmentKey {
    @MainActor
    static let defaultValue = HealthWorkoutWatcher(
        observer: StubHealthWorkoutObserver(authorized: false),
        notifier: StubNewWorkoutNotifier(),
        defaults: UserDefaults(suiteName: "preview.healthWatcher") ?? .standard
    )
}

extension EnvironmentValues {
    /// Watches Apple Health and notifies about new cardio workouts,
    /// including Garmin activities synced through Garmin Connect.
    var healthWatcher: HealthWorkoutWatcher {
        get { self[HealthWorkoutWatcherKey.self] }
        set { self[HealthWorkoutWatcherKey.self] = newValue }
    }
}
