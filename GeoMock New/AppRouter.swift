//
//  AppRouter.swift
//  Shared navigation state: which tab is showing, and whether the
//  "re-attach from Mac" guide is open. Lives outside any one view so
//  things that aren't views — a tapped notification, the Mac-connection
//  monitor — can steer the UI.
//

import SwiftUI
import Combine
import UserNotifications

enum AppTab: Hashable {
    case home
    case timer
}

final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: AppTab = .home
    @Published var showReattachGuide = false

    private init() {}
}

// MARK: - Notification taps

/// Opens the re-attach guide when the user taps an expiry reminder or its
/// "Review Steps" button. Installed once at launch (see GeoMock_NewApp).
/// It doesn't implement willPresent, so notifications stay silent while the
/// app is open on screen — the in-app banner already covers that case.
nonisolated final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    static let expiryCategory = "geomock.expiry.category"
    static let reviewAction = "geomock.expiry.review"

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let review = UNNotificationAction(identifier: NotificationRouter.reviewAction,
                                          title: "Review Steps",
                                          options: [.foreground])
        let category = UNNotificationCategory(identifier: NotificationRouter.expiryCategory,
                                              actions: [review],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        guard category == NotificationRouter.expiryCategory else { return }
        await MainActor.run {
            AppRouter.shared.showReattachGuide = true
        }
    }
}
