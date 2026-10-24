//
//  AppRouter.swift
//  Shared navigation state: which tab is showing. Lives outside any one view
//  so things that aren't views — a tapped notification, the Mac-connection
//  monitor — can steer the UI.
//

import SwiftUI
import Combine
import UserNotifications

enum AppTab: Hashable {
    case home
    case timer
    case progress
}

final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: AppTab = .home

    private init() {}
}

// MARK: - Notification taps

/// Handles notifications while the app is open and when one is tapped. Installed
/// once at launch (see GeoMock_NewApp). Expiry reminders stay silent while the app is open on screen (the in-app
/// banner covers that). The route-complete notifications are the exception: they
/// show in the app too. They only bring their own sound if the app isn't already looping the alarm itself.
nonisolated final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    /// Base name of the route-complete notifications. Every route timer schedules an alarm chain of
    /// `alarmCount` notifications, `alarmInterval` seconds apart, named "<base>.1" ... "<base>.60".
    static let routeDoneID = "geomock.routeTimer.done"

    /// The alarm sound in the app bundle: 27 s of audio (nine dings, three seconds apart). iOS plays a
    /// notification sound for 30 seconds at most, and falls back to the default tone for anything longer.
    static let alarmSoundFile = "RouteComplete.wav"
    /// Each notification is spaced this far from the last (the length of that file), so the dings
    /// carry on from one notification to the next without a gap.
    static let alarmInterval: TimeInterval = 27
    /// iOS keeps at most 64 pending notifications per app, and the expiry reminder uses 1.
    static let alarmCount = 60
    /// The first notification arrives this long after the end time, so an open app has time to
    /// start its own endless loop first and cancel the chain before anything doubles up.
    static let alarmLeadIn: TimeInterval = 1

    static let routeDoneIDs: [String] = (1...NotificationRouter.alarmCount).map { "\(NotificationRouter.routeDoneID).\($0)" }

    /// True for any notification in the alarm chain (and for the single one older versions scheduled).
    static func isRouteDone(_ id: String) -> Bool {
        id == routeDoneID || id.hasPrefix(routeDoneID + ".")
    }

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    // These use the completion-handler form of the delegate methods, not the `async` form, on purpose.
    // The `async` form makes Swift call the completion handler from whatever thread the Task ends up
    // on, and when you tap a notification UIKit's handler for it aborts unless it is called on the
    // MAIN thread ("Call must be made on main thread"). Here every path ends with the completion
    // handler being called on the main queue.

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.identifier
        DispatchQueue.main.async {
            guard NotificationRouter.isRouteDone(id) else {
                completionHandler([])
                return
            }
            // The app is open. If it is already ringing the alarm itself, show the banner only (a second
            // sound on top would just garble it). Otherwise the notification brings its own sound.
            let appIsRinging = MainActor.assumeIsolated { AlarmPlayer.shared.isPlaying }
            completionHandler(appIsRinging ? [.banner, .list] : [.banner, .list, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            // Tapping a route-complete notification opens the Timer tab.
            if NotificationRouter.isRouteDone(id) {
                MainActor.assumeIsolated { AppRouter.shared.selectedTab = .timer }
            }
            completionHandler()
        }
    }
}
