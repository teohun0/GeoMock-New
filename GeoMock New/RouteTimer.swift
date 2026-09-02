//
//  RouteTimer.swift
//  Countdown behind the Timer tab. Tap a route and it starts immediately.
//
//  At zero you get a "Route complete" notification, the same kind a text
//  message makes: your default alert tone (Settings > Sounds & Haptics), a
//  vibration and a banner on the lock screen. It is marked Time Sensitive and
//  is scheduled with iOS the moment the timer starts, so it arrives even if
//  the phone is locked, GeoMock is in the background, or the app was closed.
//
//  Like a text, it follows the silent switch (vibrate only) and Focus / Do Not
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
    /// How long the countdown runs, in seconds. Measured, not calculated.
    let durationSeconds: TimeInterval

    /// Both routes run at this fixed speed.
    static let speedKmh: Double = 82

    /// 47 min 44 s.
    static let routeSeconds: TimeInterval = 47 * 60 + 44

    /// The two routes on the Timer tab. Change `durationSeconds` here if a
    /// route turns out to take a different time.
    static let all: [TimerRoute] = [
        TimerRoute(id: "650385", title: "650385", distanceKm: 80, durationSeconds: routeSeconds),
        TimerRoute(id: "draycott", title: "Draycott", distanceKm: 80, durationSeconds: routeSeconds),
    ]

    var distanceLabel: String {
        "\(distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km"
    }

    /// The number on the route row and the first frame of the countdown.
    var duration: TimeInterval { durationSeconds }

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
    private let notificationID = NotificationRouter.routeDoneID

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

    /// Clears the finished screen and the notification.
    func dismissFinished() {
        finished = nil
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

        // Put the Dismiss button where you'll see it when you open the app.
        // The notification is not touched here: iOS delivers it at the end time by itself.
        AppRouter.shared.selectedTab = .timer
    }

    // MARK: Notification

    /// Asks for permission if needed, then schedules the "Route complete" notification
    /// for the exact end time. iOS delivers it whether or not the app is still running.
    private func scheduleEndNotification(for timer: ActiveTimer) {
        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard let self else { return }
            await self.updateAlertWarning()
            guard granted, self.active?.id == timer.id else { return }
            let delay = timer.endDate.timeIntervalSinceNow
            guard delay > 0.5 else { return }

            let content = UNMutableNotificationContent()
            content.title = "Route complete"
            content.body = "\(timer.title) · \(timer.detail)"
            content.sound = .default                    // your default alert tone, like a text
            content.interruptionLevel = .timeSensitive  // needs the capability to break through Focus
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: self.notificationID, content: content, trigger: trigger))
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

    /// Removes our notification whether it is still waiting or already on screen.
    private func clearNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
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
