//
//  RouteTimer.swift
//  Countdown behind the Timer tab. Tap a route and it starts immediately.
//
//  Each route is one timer for its whole length: distance ÷ 100 km/h
//  (650385 is 80 km = 48:00, Draycott is 81 km = 48:36). Change `distanceKm`
//  below if a GPX turns out to be a different length.
//
//  When the timer ends you get 4 "Route complete" notifications, 3 seconds
//  apart, the same kind a text message makes: your default alert tone
//  (Settings > Sounds & Haptics), a vibration and a banner on the lock screen.
//  Every notification GeoMock sends is marked Time Sensitive. They are all
//  scheduled with iOS the moment the timer starts, so they arrive even if the
//  phone is locked, GeoMock is in the background, or the app was closed.
//
//  Like a text, they follow the silent switch (vibrate only) and Focus / Do Not
//  Disturb (hidden) unless GeoMock is allowed in that Focus. Time Sensitive only
//  breaks through Focus when the app has that capability, which needs a paid
//  developer account; without it iOS delivers a normal notification.
//
//  This timer is a companion stopwatch: it does not start or stop the
//  Xcode GPX playback or the in-app simulator. Start it right when you start
//  the route.
//

import Foundation
import Combine
import UserNotifications
import UIKit

// MARK: - Routes

struct TimerRoute: Identifiable, Hashable {
    let id: String
    let title: String
    let distanceKm: Double

    /// Both routes run at this fixed speed.
    static let speedKmh: Double = 100

    /// The two routes on the Timer tab.
    static let all: [TimerRoute] = [
        TimerRoute(id: "650385", title: "650385", distanceKm: 80),
        TimerRoute(id: "draycott", title: "Draycott", distanceKm: 81),
    ]

    var distanceLabel: String {
        "\(distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km"
    }

    /// Distance ÷ speed for the whole route, in whole seconds (rounded up).
    /// 80 km at 100 km/h = 48:00, 81 km = 48:36.
    var duration: TimeInterval {
        (distanceKm * 3600 / TimerRoute.speedKmh).rounded(.up)
    }

    var detail: String {
        "\(distanceLabel) at \(Int(TimerRoute.speedKmh)) km/h"
    }
}

enum TimerFormat {
    /// "58:33", or "1:13:51" once it's an hour or more.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - A running timer (Codable so it survives the app being killed mid-route)

struct ActiveTimer: Codable, Equatable, Identifiable {
    var id = UUID()
    let title: String
    let detail: String
    let startDate: Date
    let endDate: Date

    var totalDuration: TimeInterval { endDate.timeIntervalSince(startDate) }

    /// Shown on screen and used as the notification title.
    var completionTitle: String { "Route complete" }

    var completionBody: String { "\(title) · \(detail)" }
}

/// The ticking number lives in its own object so only the countdown view
/// redraws each second — not the whole app.
final class TimerClock: ObservableObject {
    @Published var remaining: TimeInterval = 0
}

// MARK: - Store

final class RouteTimerStore: ObservableObject {
    @Published private(set) var active: ActiveTimer?
    @Published private(set) var finished: ActiveTimer?
    /// Set when notifications are off (or silenced) for GeoMock, so nothing would
    /// alert at the end. nil = all good.
    @Published private(set) var alertWarning: String?

    let clock = TimerClock()

    private let storageKey = "geomock.routeTimer.active"
    /// Every notification this store can have scheduled or on screen: the 4-notification
    /// burst, plus the single one older versions used so it can't linger after an update.
    private let notificationIDs = NotificationRouter.routeDoneIDs + [NotificationRouter.routeDoneID]

    private var ticker: AnyCancellable?
    private var lastShownSecond = -1

    init() {
        restore()
    }

    // MARK: Controls

    /// Starts counting down right now. Replaces any timer already running.
    func start(title: String, detail: String, duration: TimeInterval) {
        guard duration >= 1 else { return }
        stopTicking()
        clearNotification()

        let now = Date()
        let timer = ActiveTimer(title: title,
                                detail: detail,
                                startDate: now,
                                endDate: now.addingTimeInterval(duration))
        finished = nil
        persist(timer)
        begin(timer)
        scheduleEndNotification(for: timer)
    }

    /// Shared by start() and restore(): everything that has to be running while a timer counts down.
    private func begin(_ timer: ActiveTimer) {
        active = timer
        let left = max(0, timer.endDate.timeIntervalSinceNow)
        lastShownSecond = Int(left.rounded(.up))
        clock.remaining = left
        startTicking()
    }

    /// Stops the timer straight away, no confirmation.
    func cancel() {
        stopTicking()
        active = nil
        alertWarning = nil
        clock.remaining = 0
        clearPersisted()
        clearNotification()
    }

    /// Clears the finished screen and the notifications.
    func dismissFinished() {
        finished = nil
        clearPersisted()
        clearNotification()
    }

    /// Call when the app returns to the foreground.
    func refresh() {
        tick()
        if let timer = active {
            // The countdown isn't redrawn while the app is away; catch it up now.
            let left = max(0, timer.endDate.timeIntervalSinceNow)
            lastShownSecond = Int(left.rounded(.up))
            clock.remaining = left
            Task { await updateAlertWarning() }
        }
    }

    // MARK: Ticking

    private func startTicking() {
        // Checks twice a second so the end is caught promptly, but only
        // publishes when the displayed second changes, and never while the app
        // is in the background, where there's nothing on screen to update.
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard let timer = active else { return }
        let left = timer.endDate.timeIntervalSinceNow
        if left <= 0 {
            finish(timer)
        } else if UIApplication.shared.applicationState == .active {
            let shown = Int(left.rounded(.up))
            if shown != lastShownSecond {
                lastShownSecond = shown
                clock.remaining = left
            }
        }
    }

    private func finish(_ timer: ActiveTimer) {
        stopTicking()
        active = nil
        alertWarning = nil
        clock.remaining = 0
        finished = timer
        clearPersisted()

        // Put the dismiss button where you'll see it when you open the app.
        // The notifications are not touched here: iOS delivers them at the end time by itself.
        AppRouter.shared.selectedTab = .timer
    }

    // MARK: Notification

    /// Asks for permission if needed, then schedules the end-of-route notifications: 4 of them,
    /// 3 seconds apart, the first at the exact end time. iOS delivers them whether or not the app
    /// is still running.
    private func scheduleEndNotification(for timer: ActiveTimer) {
        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard let self else { return }
            await self.updateAlertWarning()
            guard granted else { return }

            for (index, id) in NotificationRouter.routeDoneIDs.enumerated() {
                // Stop if the timer was cancelled or replaced while we were scheduling.
                guard self.active?.id == timer.id else { return }

                // Worked out from the end date each time, so the gaps stay exact however long each add takes.
                let delay = timer.endDate.timeIntervalSinceNow + Double(index) * NotificationRouter.burstGap
                guard delay > 0.5 else { continue }

                let content = UNMutableNotificationContent()
                content.title = timer.completionTitle
                content.body = timer.completionBody
                content.sound = .default                    // your default alert tone, like a text
                content.interruptionLevel = .timeSensitive  // needs the capability to break through Focus
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    /// Tells the Timer screen when notifications are switched off or silenced for GeoMock.
    private func updateAlertWarning() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied {
            alertWarning = "Notifications are off for GeoMock, so nothing will alert at the end. Turn them on in Settings > Notifications > GeoMock."
        } else if settings.authorizationStatus == .authorized && settings.soundSetting == .disabled {
            alertWarning = "Sounds are off for GeoMock notifications, so the end will only show a banner. Turn Sounds on in Settings > Notifications > GeoMock."
        } else {
            alertWarning = nil
        }
    }

    /// Removes our notifications whether they are still waiting or already on screen.
    private func clearNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: notificationIDs)
        center.removeDeliveredNotifications(withIdentifiers: notificationIDs)
    }

    // MARK: Persistence

    private func persist(_ timer: ActiveTimer) {
        if let data = try? JSONEncoder().encode(timer) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func clearPersisted() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(ActiveTimer.self, from: data) else { return }
        if saved.endDate > Date() {
            begin(saved)
            Task { await updateAlertWarning() }
        } else {
            finished = saved
            clearPersisted()
        }
    }
}
