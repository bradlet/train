//
//  NewWorkoutNotifier.swift
//  Train
//
//  The "new workout to review" notification (#37). `NewWorkoutNotification`
//  is the pure content (what it says, which workouts it carries);
//  `NewWorkoutNotifying` posts it, live through `UNUserNotificationCenter`
//  and as a recorder in tests. Tapping it opens the Apple Health import
//  sheet with those workouts ticked (`HealthImportRouter`).
//

import Foundation
import UserNotifications

/// Whether Train may show notifications.
nonisolated enum NotificationPermission: Equatable, Sendable {
    /// Never asked.
    case notDetermined
    /// The athlete turned them off.
    case denied
    /// Allowed (including provisional and ephemeral).
    case allowed
}

/// The content of one new-workout notification.
struct NewWorkoutNotification: Equatable, Sendable {
    /// Replaces an earlier, still-unread notification for the same workouts.
    let identifier: String
    let title: String
    let body: String
    /// HealthKit UUIDs the import sheet should tick.
    let workoutIDs: [String]

    /// The `userInfo` key carrying `workoutIDs`.
    static let workoutIDsKey = "healthWorkoutIDs"
    /// The notification's category, so a tap can be recognised.
    static let category = "train.newHealthWorkouts"

    /// The notification for `workouts`, or `nil` when there are none. One
    /// workout names its type, distance and time ("New run from Garmin");
    /// several are counted.
    /// - Parameters:
    ///   - workouts: The new cardio workouts, oldest first.
    ///   - metric: Whether to show kilometres.
    static func make(for workouts: [HealthKitWorkout], metric: Bool) -> NewWorkoutNotification? {
        guard !workouts.isEmpty else { return nil }
        let ids = workouts.map(\.id)
        let allGarmin = workouts.allSatisfy(\.isFromGarmin)
        let tap = "Tap to review and import."
        if workouts.count == 1, let workout = workouts.first {
            let type = HealthKitWorkoutMapper.exerciseType(for: workout.activityType)
            let noun = type == .other ? "workout" : type.rawValue.lowercased()
            let origin = workout.isFromGarmin ? "Garmin" : "Apple Health"
            var parts: [String] = []
            if let miles = workout.distanceMiles, miles > 0 {
                parts.append(miles.formattedDistance(metric: metric))
            }
            parts.append(Int(workout.duration).formattedDuration)
            return NewWorkoutNotification(
                identifier: "health.\(workout.id)",
                title: "New \(noun) from \(origin)",
                body: parts.joined(separator: " · ") + ". " + tap,
                workoutIDs: ids
            )
        }
        let origin = allGarmin ? "from Garmin" : "in Apple Health"
        return NewWorkoutNotification(
            identifier: "health.batch.\(ids[0]).\(ids.count)",
            title: "\(workouts.count) new workouts \(origin)",
            body: tap,
            workoutIDs: ids
        )
    }

    /// The workout IDs a tapped notification carries, or `nil` when it
    /// isn't a new-workout notification.
    /// - Parameter userInfo: The notification's `userInfo`.
    static func workoutIDs(from userInfo: [AnyHashable: Any]) -> [String]? {
        guard let ids = userInfo[workoutIDsKey] as? [String], !ids.isEmpty else { return nil }
        return ids
    }
}

/// Posts new-workout notifications.
protocol NewWorkoutNotifying: Sendable {
    /// Asks for permission when it hasn't been asked yet, and returns the
    /// result. The system prompts at most once.
    func requestPermission() async -> NotificationPermission
    /// The current permission, without prompting.
    func permission() async -> NotificationPermission
    /// Shows the notification.
    func post(_ notification: NewWorkoutNotification) async
}

// MARK: - Live

/// Posts through `UNUserNotificationCenter`.
struct LiveNewWorkoutNotifier: NewWorkoutNotifying {

    func requestPermission() async -> NotificationPermission {
        let center = UNUserNotificationCenter.current()
        if await permission() == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        return await permission()
    }

    func permission() async -> NotificationPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    func post(_ notification: NewWorkoutNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = NewWorkoutNotification.category
        content.userInfo = [NewWorkoutNotification.workoutIDsKey: notification.workoutIDs]
        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Stub

/// Records what would have been posted. Never shows anything.
actor StubNewWorkoutNotifier: NewWorkoutNotifying {
    /// What `requestPermission` grants.
    var grant: NotificationPermission
    /// The current permission.
    private(set) var current: NotificationPermission = .notDetermined
    /// Everything posted, in order.
    private(set) var posted: [NewWorkoutNotification] = []
    /// How many times permission was requested.
    private(set) var requestCount = 0

    /// Creates a stub that grants `grant` when asked.
    init(grant: NotificationPermission = .allowed) {
        self.grant = grant
    }

    func requestPermission() async -> NotificationPermission {
        requestCount += 1
        if current == .notDetermined { current = grant }
        return current
    }

    func permission() async -> NotificationPermission { current }

    func post(_ notification: NewWorkoutNotification) async {
        posted.append(notification)
    }
}
