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
/// show with their sound even in the app, like a text arriving.
nonisolated final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    /// Base name of the route-complete notifications. The end of every route timer sends a burst of
    /// `burstCount` notifications, `burstGap` seconds apart, named "<base>.1" ... "<base>.4".
    static let routeDoneID = "geomock.routeTimer.done"
    static let burstCount = 4
    static let burstGap: TimeInterval = 3
    static let routeDoneIDs: [String] = (1...NotificationRouter.burstCount).map { "\(NotificationRouter.routeDoneID).\($0)" }

    /// True for any notification in the burst (and for the single one older versions scheduled).
    static func isRouteDone(_ id: String) -> Bool {
        id == routeDoneID || id.hasPrefix(routeDoneID + ".")
    }

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        NotificationRouter.isRouteDone(notification.request.identifier) ? [.banner, .list, .sound] : []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        // Tapping a route-complete notification opens the Timer tab.
        guard NotificationRouter.isRouteDone(response.notification.request.identifier) else { return }
        await MainActor.run {
            AppRouter.shared.selectedTab = .timer
        }
    }
}
