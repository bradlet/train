//
//  HealthWorkoutWatcher.swift
//  Train
//
//  New-workout notifications (#37). When any app saves a cardio workout to
//  Apple Health, Train posts one notification; tapping it opens the Apple
//  Health import sheet with that workout ticked. Nothing imports without the
//  athlete's confirmation.
//
//  Garmin rides the same path: Garmin Connect writes activities to Health,
//  and each workout names the app that saved it. Garmin counts as connected
//  once Health holds a workout from Garmin Connect, and Garmin activities
//  notify by their own switch, which is on by default, so they start the
//  moment Garmin is connected. Both switches live in this device's
//  `UserDefaults`; notifications are per device and never sync.
//
//  The watcher starts from `TrainApp.init`, so the observer query is in place
//  when iOS relaunches Train in the background for a new workout. It only
//  runs once Apple Health has been connected (access requested), and never
//  prompts for Health access itself.
//

import Foundation
import Observation
import SwiftData

/// Watches Apple Health and notifies about new cardio workouts.
@MainActor
@Observable
final class HealthWorkoutWatcher {

    /// Whether to notify about new workouts from Apple Watch and other
    /// non-Garmin apps. On by default.
    var notifiesHealth: Bool {
        didSet {
            defaults.set(notifiesHealth, forKey: Keys.notifiesHealth)
            Task { await syncObserving() }
        }
    }

    /// Whether to notify about new Garmin activities. On by default, so it
    /// takes effect as soon as Garmin is connected.
    var notifiesGarmin: Bool {
        didSet {
            defaults.set(notifiesGarmin, forKey: Keys.notifiesGarmin)
            Task { await syncObserving() }
        }
    }

    /// Whether Garmin Connect has saved a workout to Health.
    private(set) var isGarminConnected: Bool
    /// Whether Apple Health has been connected (access requested).
    private(set) var isHealthConnected = false
    /// Whether Train may post notifications.
    private(set) var notificationPermission: NotificationPermission = .notDetermined
    /// Whether the observer query is running.
    private(set) var isObserving = false

    /// How recent a workout must be to notify. An older one (a backfill, or
    /// a watch syncing days later) still imports by hand, just silently.
    static let recentWindow: TimeInterval = 2 * 86_400

    /// `UserDefaults` keys.
    enum Keys {
        static let notifiesHealth = "connections.health.notifyNewWorkouts"
        static let notifiesGarmin = "connections.garmin.notifyNewActivities"
        static let garminConnected = "connections.garmin.connectedViaHealth"
        static let anchor = "connections.health.workoutAnchor"
    }

    @ObservationIgnored private let observer: any HealthWorkoutObserving
    @ObservationIgnored private let notifier: any NewWorkoutNotifying
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private weak var modelContainer: ModelContainer?
    /// A check is fetching; another change arrived meanwhile.
    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var needsRecheck = false

    /// Creates a watcher.
    /// - Parameters:
    ///   - observer: The HealthKit side (live or stub).
    ///   - notifier: Posts the notification (live or stub).
    ///   - defaults: Where the switches and the anchor live.
    ///   - now: The clock, for the recency window.
    init(
        observer: any HealthWorkoutObserving,
        notifier: any NewWorkoutNotifying,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.observer = observer
        self.notifier = notifier
        self.defaults = defaults
        self.now = now
        notifiesHealth = defaults.object(forKey: Keys.notifiesHealth) as? Bool ?? true
        notifiesGarmin = defaults.object(forKey: Keys.notifiesGarmin) as? Bool ?? true
        isGarminConnected = defaults.bool(forKey: Keys.garminConnected)
    }

    /// Whether any switch is on.
    var notifiesAnything: Bool { notifiesHealth || notifiesGarmin }

    // MARK: - Lifecycle

    /// Starts watching if Apple Health is connected. Safe to call again,
    /// e.g. right after the import sheet first gets Health access; the
    /// first call with Health connected asks for notification permission.
    /// - Parameter container: The store, for what's already imported.
    func start(container: ModelContainer) async {
        modelContainer = container
        isHealthConnected = await observer.hasRequestedAuthorization()
        guard isHealthConnected else { return }
        await refreshGarminConnection()
        await syncObserving()
        // Catch anything saved while Train wasn't running; on a first run
        // this only records the baseline anchor.
        if isObserving {
            await checkForNewWorkouts()
        }
    }

    /// Re-reads the notification permission, e.g. when Connections appears
    /// after the athlete visited iOS Settings.
    func refreshPermission() async {
        notificationPermission = await notifier.permission()
    }

    /// Starts or stops the observer to match the switches. The switches
    /// call it themselves; tests await it directly.
    func syncObserving() async {
        guard isHealthConnected else { return }
        guard notifiesAnything else {
            await observer.stopObserving()
            isObserving = false
            return
        }
        notificationPermission = await notifier.requestPermission()
        guard !isObserving else { return }
        do {
            try await observer.startObserving { [weak self] in
                await self?.checkForNewWorkouts()
            }
            isObserving = true
        } catch {
            isObserving = false
        }
    }

    /// Marks Garmin connected when Garmin Connect has saved a workout.
    private func refreshGarminConnection() async {
        guard !isGarminConnected, let ids = try? await observer.workoutSourceBundleIDs() else { return }
        if ids.contains(where: { HealthKitWorkout.isGarmin(bundleID: $0) }) {
            markGarminConnected()
        }
    }

    private func markGarminConnected() {
        isGarminConnected = true
        defaults.set(true, forKey: Keys.garminConnected)
    }

    // MARK: - New workouts

    /// Fetches what's new since the last look and posts one notification
    /// for the workouts worth reviewing. The very first fetch only records
    /// where Health is, so a fresh install never notifies about history.
    func checkForNewWorkouts() async {
        // One check at a time, so two overlapping wake-ups can't both read
        // the same anchor and post the same workout twice.
        guard !isChecking else {
            needsRecheck = true
            return
        }
        isChecking = true
        repeat {
            needsRecheck = false
            await check()
        } while needsRecheck
        isChecking = false
    }

    /// One fetch-filter-post pass.
    private func check() async {
        let anchor = defaults.data(forKey: Keys.anchor)
        guard let result = try? await observer.fetchWorkouts(after: anchor) else { return }
        if let next = result.anchor {
            defaults.set(next, forKey: Keys.anchor)
        }
        if result.workouts.contains(where: \.isFromGarmin) {
            markGarminConnected()
        }
        guard anchor != nil else { return }
        let known = modelContainer.map { TrainingImporter.knownIDs(in: ModelContext($0)) } ?? []
        let worth = Self.workoutsToNotify(
            result.workouts,
            known: known,
            notifiesHealth: notifiesHealth,
            notifiesGarmin: notifiesGarmin,
            now: now()
        )
        let metric = modelContainer.flatMap { try? ModelContext($0).fetch(FetchDescriptor<AppConfiguration>()).first?.useMetricUnits } ?? false
        guard let notification = NewWorkoutNotification.make(for: worth, metric: metric) else { return }
        await notifier.post(notification)
    }

    /// The new workouts worth a notification: cardio, recent, not already
    /// in Train, and from a source whose switch is on. Oldest first.
    /// - Parameters:
    ///   - workouts: Workouts new to Health since the last look.
    ///   - known: Anchors already in Train (`TrainingImporter.knownIDs`).
    ///   - notifiesHealth: The non-Garmin switch.
    ///   - notifiesGarmin: The Garmin switch.
    ///   - now: The current time.
    static func workoutsToNotify(
        _ workouts: [HealthKitWorkout],
        known: Set<String>,
        notifiesHealth: Bool,
        notifiesGarmin: Bool,
        now: Date
    ) -> [HealthKitWorkout] {
        workouts
            .filter { HealthKitWorkoutMapper.isCardio($0.activityType) }
            .filter { !known.contains($0.id) }
            .filter { now.timeIntervalSince($0.startDate) <= recentWindow }
            .filter { $0.isFromGarmin ? notifiesGarmin : notifiesHealth }
            .sorted { $0.startDate < $1.startDate }
    }
}

/// Carries a tapped new-workout notification to the Apple Health import
/// sheet. The shared instance because the notification delegate routes
/// through it from outside SwiftUI.
@MainActor
@Observable
final class HealthImportRouter {
    /// The app's router.
    static let shared = HealthImportRouter()

    /// The import the app root should present, if any.
    var pending: HealthImportRequest?

    /// Opens the import sheet with these workouts ticked.
    /// - Parameter workoutIDs: HealthKit UUIDs from the notification.
    func route(workoutIDs: [String]) {
        pending = HealthImportRequest(workoutIDs: Set(workoutIDs))
    }
}

/// An Apple Health import opened from a notification.
struct HealthImportRequest: Identifiable, Equatable {
    let id = UUID()
    /// Workouts to tick in the sheet.
    let workoutIDs: Set<String>
}
