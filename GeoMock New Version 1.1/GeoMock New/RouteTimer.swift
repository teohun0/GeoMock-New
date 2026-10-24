//
//  RouteTimer.swift
//  Countdown behind the Timer tab. Tap a route and it starts immediately.
//
//  Each route is one timer for its whole length: distance ÷ 100 km/h
//  (650385 is 80 km = 48:00, Draycott is 81 km = 48:36). Change `distanceKm`
//  below if a GPX turns out to be a different length.
//
//  When the timer ends, GeoMock rings the "Route complete" alarm (RouteComplete.wav)
//  until you press Stop Alarm in the app:
//
//    - App open: GeoMock plays the sound itself on an endless loop (AlarmPlayer).
//      That ignores the silent switch and Focus, like the Clock app.
//
//    - Phone locked, GeoMock in the background or closed: iOS stops a notification
//      sound at 30 seconds, and RouteComplete.wav is 27 s long (nine dings), so 60
//      "Route complete" notifications are scheduled back to back, 27 s apart, each
//      carrying that sound. That is about 27 minutes of ringing with no app running.
//      They are all handed to iOS the moment the timer starts. Opening GeoMock
//      switches over to the endless loop and cancels the ones still waiting.
//
//  Stop Alarm ends everything: the loop and every notification still waiting.
//  The finished timer is kept until then, so the alarm rings again if the app is
//  killed and reopened.
//
//  Every notification GeoMock sends is marked Time Sensitive. Notification sounds
//  follow the silent switch (vibrate only) and Focus / Do Not Disturb (hidden) unless
//  GeoMock is allowed in that Focus. Time Sensitive only breaks through Focus when the
//  app has that capability, which needs a paid developer account; without it iOS
//  delivers a normal notification. The in-app loop is not affected by any of that.
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
    /// A timer that has run out and is still ringing. nil once Stop Alarm has been pressed.
    @Published private(set) var finished: ActiveTimer?
    /// Set when notifications are off (or silenced) for GeoMock, so nothing would
    /// alert at the end while the app is closed. nil = all good.
    @Published private(set) var alertWarning: String?

    let clock = TimerClock()

    private let storageKey = "geomock.routeTimer.active"
    /// Every notification this store can have scheduled or on screen: the whole alarm
    /// chain, plus the single one older versions used so it can't linger after an update.
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
        AlarmPlayer.shared.stop()
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

    /// Stop Alarm: ends the endless loop, clears the finished screen and cancels
    /// any alarm notifications still waiting or on the lock screen.
    func dismissFinished() {
        AlarmPlayer.shared.stop()
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
        // The alarm is still going off (you opened the app from the lock screen, or the
        // sound was cut short): take over with the endless in-app loop.
        if finished != nil { startAlarm() }
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
        // The saved timer is NOT cleared here. It stays until Stop Alarm, so the alarm
        // still rings if the app is killed and reopened.

        // Put the Stop Alarm button where you'll see it when you open the app.
        AppRouter.shared.selectedTab = .timer
        startAlarm()
    }

    /// Starts the endless in-app loop. Once it is playing, the notification chain would
    /// only double the sound up, so whatever is still waiting is cancelled. If iOS refuses
    /// to start the audio (it can, from the background), the notifications stay as the fallback.
    private func startAlarm() {
        guard finished != nil, !AlarmPlayer.shared.isPlaying else { return }
        // Starting takes a moment (the audio session is activated off the main thread), so the
        // answer arrives in the completion handler.
        AlarmPlayer.shared.start { [weak self] started in
            if started { self?.clearNotification() }
        }
    }

    // MARK: Notification

    /// Asks for permission if needed, then schedules the alarm chain: 60 notifications, 27 s
    /// apart (the length of RouteComplete.wav), starting just after the end time. iOS delivers
    /// them whether or not the app is still running.
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
                let delay = timer.endDate.timeIntervalSinceNow
                    + NotificationRouter.alarmLeadIn
                    + Double(index) * NotificationRouter.alarmInterval
                guard delay > 0.5 else { continue }

                let content = UNMutableNotificationContent()
                content.title = timer.completionTitle
                content.body = timer.completionBody
                content.sound = UNNotificationSound(named: UNNotificationSoundName(NotificationRouter.alarmSoundFile))
                content.interruptionLevel = .timeSensitive  // needs the capability to break through Focus
                content.threadIdentifier = NotificationRouter.routeDoneID   // stacks the chain as one group
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    /// Tells the Timer screen when notifications are switched off or silenced for GeoMock.
    private func updateAlertWarning() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied {
            alertWarning = "Notifications are off for GeoMock, so nothing will ring at the end while the app is closed. Turn them on in Settings > Notifications > GeoMock."
        } else if settings.authorizationStatus == .authorized && settings.alertSetting == .disabled {
            alertWarning = "Alerts are off for GeoMock, so no banner will appear at the end. Turn Alerts on in Settings > Notifications > GeoMock."
        } else if settings.authorizationStatus == .authorized && settings.soundSetting == .disabled {
            alertWarning = "Sounds are off for GeoMock notifications, so the end will only show a banner. Turn Sounds on in Settings > Notifications > GeoMock."
        } else if settings.authorizationStatus == .authorized && settings.scheduledDeliverySetting == .enabled {
            alertWarning = "GeoMock is set to Scheduled Summary, so iOS can hold the alert back until the next summary. Choose Deliver Immediately in Settings > Notifications > GeoMock."
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
            // It ran out while the app was closed. The alarm keeps going until Stop Alarm is pressed.
            finished = saved
            startAlarm()
            // Not set directly: this runs while the root view is being built.
            Task { AppRouter.shared.selectedTab = .timer }
        }
    }
}
