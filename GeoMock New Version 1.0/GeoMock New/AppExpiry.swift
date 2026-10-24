//
//  AppExpiry.swift
//  A plain 7-day countdown for re-attaching the app from the Mac. Apps
//  installed from Xcode with a free Apple ID stop opening after 7 days, so
//  the app keeps its own 7-day timer and sends one reminder a day before it
//  runs out. It doesn't look at the signing at all: the timer starts the
//  first time the app opens and starts over when you tap "Reset 7-day timer"
//  on the expiry banner (do that once Xcode has reinstalled the app).
//

import Foundation
import Combine
import UserNotifications

final class AppExpiryStore: ObservableObject {
    /// How long an Xcode install lasts with a free Apple ID.
    static let lifetime: TimeInterval = 7 * 24 * 3600
    /// The reminder arrives this long before the 7 days are up.
    static let reminderLead: TimeInterval = 24 * 3600

    @Published private(set) var expiryDate: Date
    @Published private(set) var notificationsDenied = false

    private let startKey = "geomock.expiry.start"
    // ".v2" so the reminder is rescheduled once with its new wording.
    private let scheduledKey = "geomock.expiry.scheduledFor.v2"
    private let reminderID = "geomock.expiry.1d"
    /// Reminders an earlier version scheduled; cleared so they can't fire on a stale date.
    private let legacyReminderIDs = ["geomock.expiry.2d", "geomock.expiry.3h", "geomock.expiry.0"]

    init() {
        let defaults = UserDefaults.standard
        var start = defaults.double(forKey: startKey)
        if start == 0 {                       // first launch: the 7 days start now
            start = Date().timeIntervalSince1970
            defaults.set(start, forKey: startKey)
        }
        expiryDate = Date(timeIntervalSince1970: start + Self.lifetime)
        Task { await syncReminder() }
    }

    /// The banner turns orange once the reminder window starts.
    var isWarning: Bool {
        expiryDate.timeIntervalSinceNow <= Self.reminderLead
    }

    /// Call when the app returns to the foreground.
    func refresh() {
        objectWillChange.send()               // re-evaluate isWarning
        Task { await syncReminder() }
    }

    /// Starts a fresh 7 days from now and moves the reminder to match.
    /// Tap this once Xcode has reinstalled the app.
    @discardableResult
    func resetTimer() async -> Date {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: startKey)
        expiryDate = now.addingTimeInterval(Self.lifetime)
        await syncReminder(force: true)
        return expiryDate
    }

    private func syncReminder(force: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        notificationsDenied = (status == .denied)
        guard status != .denied else { return }

        // Already set for this exact expiry date: nothing to do.
        let defaults = UserDefaults.standard
        if !force, status == .authorized, defaults.double(forKey: scheduledKey) == expiryDate.timeIntervalSince1970 { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        notificationsDenied = !granted
        guard granted else { return }

        let expiry = expiryDate               // read after the awaits, in case a reset happened meanwhile
        center.removePendingNotificationRequests(withIdentifiers: [reminderID] + legacyReminderIDs)

        let fireDate = expiry.addingTimeInterval(-Self.reminderLead)
        if fireDate > Date().addingTimeInterval(5) {
            let content = UNMutableNotificationContent()
            content.title = "GeoMock expires tomorrow"
            content.body = "Plug your iPhone into your Mac and run it from Xcode to renew it."
            content.sound = .default
            content.interruptionLevel = .timeSensitive   // needs the capability to break through Focus

            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger))
        }
        defaults.set(expiry.timeIntervalSince1970, forKey: scheduledKey)
    }
}
