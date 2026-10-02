//
//  AppExpiry.swift
//  Apps installed from Xcode stop opening once their provisioning profile
//  expires (7 days with a free Apple ID). The profile is embedded in the
//  app as embedded.mobileprovision, so the app can read its own expiry
//  date and warn before it happens.
//
//  Builds with no embedded profile (Simulator, TestFlight, App Store) have
//  no expiry date here, so nothing is shown and nothing is scheduled.
//

import Foundation
import Combine
import UserNotifications

// MARK: - Reading the expiry date

enum ProvisioningProfile {
    /// The date this install's signing expires, or nil if it can't be read.
    static func expiryDate() -> Date? {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path) else { return nil }

        // The file is a signed blob with a plain-text XML plist inside it.
        // Cut that plist out and read it.
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound else { return nil }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData,
                                                                       options: [],
                                                                       format: nil) as? [String: Any]
        else { return nil }

        return plist["ExpirationDate"] as? Date
    }
}

// MARK: - Store

final class AppExpiryStore: ObservableObject {
    @Published private(set) var expiryDate: Date?
    @Published private(set) var notificationsDenied = false

    /// The banner turns orange once expiry is this close.
    static let warningWindow: TimeInterval = 2 * 24 * 3600

    private struct Reminder {
        let id: String
        let lead: TimeInterval   // how long before expiry it fires
        let title: String
        let body: String
    }

    private let reminders: [Reminder] = [
        Reminder(id: "geomock.expiry.2d", lead: 48 * 3600,
                 title: "GeoMock expires in 2 days",
                 body: "Plug your iPhone into your Mac and run it from Xcode to renew it. Tap to see the steps."),
        Reminder(id: "geomock.expiry.1d", lead: 24 * 3600,
                 title: "GeoMock expires tomorrow",
                 body: "Re-attach it from your Mac in Xcode before it stops opening. Tap to see the steps."),
        Reminder(id: "geomock.expiry.3h", lead: 3 * 3600,
                 title: "GeoMock expires in 3 hours",
                 body: "Re-attach it from your Mac in Xcode now. Tap to see the steps."),
        Reminder(id: "geomock.expiry.0", lead: 0,
                 title: "GeoMock has expired",
                 body: "Plug your iPhone into your Mac and run it from Xcode to start it up again."),
    ]

    init() {
        refresh()
    }

    var isWarning: Bool {
        guard let date = expiryDate else { return false }
        return date.timeIntervalSinceNow <= Self.warningWindow
    }

    /// Re-read the profile and re-sync the reminders. Safe to call often —
    /// installing a fresh build from Xcode gives a new expiry date, and this
    /// replaces the old reminders with ones for the new date.
    func refresh() {
        let date = ProvisioningProfile.expiryDate()
        expiryDate = date
        Task { await syncNotifications(for: date) }
    }

    private func syncNotifications(for date: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: reminders.map(\.id))
        guard let date else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        notificationsDenied = !granted
        guard granted else { return }

        let now = Date()
        for reminder in reminders {
            let fireDate = date.addingTimeInterval(-reminder.lead)
            guard fireDate > now.addingTimeInterval(5) else { continue }   // already past

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = NotificationRouter.expiryCategory

            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                        from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id,
                                                content: content,
                                                trigger: trigger)
            try? await center.add(request)
        }
    }
}
