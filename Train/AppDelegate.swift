//
//  AppDelegate.swift
//  Train
//
//  UIKit hooks SwiftUI has no equivalent for. Today that's only the
//  notification delegate (#37): a tapped new-workout notification opens
//  the Apple Health import sheet through `HealthImportRouter`, and one that
//  arrives while Train is open still shows as a banner.
//

import UIKit
import UserNotifications

/// The app delegate, adapted into `TrainApp`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Installs the notification delegate before launch finishes, as iOS
    /// requires for a tap that launched the app to be delivered.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Shows a new-workout notification even while Train is in front.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Routes a tapped new-workout notification to the import sheet.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let ids = NewWorkoutNotification.workoutIDs(from: response.notification.request.content.userInfo) else { return }
        await MainActor.run {
            HealthImportRouter.shared.route(workoutIDs: ids)
        }
    }
}
