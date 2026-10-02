//
//  RouteTimer.swift
//  Countdown behind the Timer tab. Tap a route and it starts immediately.
//  At zero the phone rings (repeating ding-ding) and vibrates until you tap
//  Dismiss in the app.
//
//  How it rings in silent mode, in Focus / Do Not Disturb, and with the phone locked:
//    • While a timer runs, the app loops an inaudible audio file (Silence.wav)
//      on a .playback audio session. With the "audio" background mode (see
//      GeoMock-New-Info.plist) that keeps the app running when you lock the
//      phone or switch to Google Maps.
//    • At zero the app plays the ding itself, in a loop. App audio on a
//      .playback session ignores the silent switch, and Focus only filters
//      notifications, not app audio. Vibration uses the system vibrate sound.
//    • It tries to raise the media volume to maximum (see MaxVolume.swift)
//      and restores it when you dismiss.
//    • Backup: a notification is scheduled 2 seconds AFTER the end time in case
//      iOS closes the app. The app cancels it when it rings first. Notifications
//      always follow silent mode and Focus, so this is a last resort.
//
//  Don't swipe GeoMock away in the app switcher during a timer — that stops
//  everything, including the background audio.
//
//  This timer is a companion stopwatch — it does not start or stop the
//  Xcode GPX playback or the in-app simulator. Start it right when you start
//  the route.
//

import Foundation
import Combine
import UserNotifications
import AVFoundation
import AudioToolbox
import UIKit

// MARK: - Routes

struct TimerRoute: Identifiable, Hashable {
    let id: String
    let title: String
    let distanceKm: Double

    /// Both routes run at this fixed speed.
    static let speedKmh: Double = 82

    /// The two routes on the Timer tab. Change `distanceKm` here if a GPX
    /// turns out to be a slightly different length than 80 km.
    static let all: [TimerRoute] = [
        TimerRoute(id: "650385", title: "650385", distanceKm: 80),
        TimerRoute(id: "draycott", title: "Draycott", distanceKm: 80),
    ]

    var distanceLabel: String {
        "\(distanceKm.formatted(.number.precision(.fractionLength(0...1)))) km"
    }

    /// Distance ÷ speed, in whole seconds (rounded up) so the number on the
    /// route row and the first frame of the countdown always match.
    var duration: TimeInterval {
        (distanceKm / TimerRoute.speedKmh * 3600).rounded(.up)
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
    /// True while the end-of-route sound is playing, until you dismiss it.
    @Published private(set) var isRinging = false
    /// nil = no timer yet, true = background audio is running, false = it couldn't start.
    @Published private(set) var keepAliveOK: Bool?

    let clock = TimerClock()

    private let storageKey = "geomock.routeTimer.active"
    private let notificationID = "geomock.routeTimer.done"
    /// The backup notification fires this long after the end time, so the
    /// app (if still alive) always rings first and cancels it.
    private let backupDelay: TimeInterval = 2

    private var ticker: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var lastShownSecond = -1
    private var keepAlive: AVAudioPlayer?     // silent loop that keeps the app running
    private var ringPlayer: AVAudioPlayer?    // the ding loop
    private var ringTask: Task<Void, Never>?  // repeating vibration

    init() {
        restore()
        observeAudioInterruptions()
    }

    // MARK: Controls

    /// Starts counting down right now. Replaces any timer already running.
    func start(title: String, detail: String, duration: TimeInterval) {
        guard duration >= 1 else { return }
        stopTicking()
        stopRinging()
        removePendingNotification()

        let now = Date()
        let timer = ActiveTimer(title: title,
                                detail: detail,
                                startDate: now,
                                endDate: now.addingTimeInterval(duration))
        active = timer
        finished = nil
        lastShownSecond = Int(duration.rounded(.up))
        clock.remaining = duration
        persist(timer)
        startTicking()
        startKeepAlive()
        MaxVolume.shared.prepare()
        scheduleBackupNotification(for: timer)
    }

    /// Stops the timer straight away — no confirmation.
    func cancel() {
        stopTicking()
        stopKeepAlive(releaseSession: true)
        active = nil
        keepAliveOK = nil
        clock.remaining = 0
        clearPersisted()
        removePendingNotification()
    }

    /// Stops the ring and clears the finished screen.
    func dismissFinished() {
        stopRinging()
        finished = nil
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
    }

    /// Call when the app returns to the foreground.
    func refresh() {
        tick(live: false)
        if let timer = active {
            // The countdown isn't redrawn while the app is away; catch it up now.
            let left = max(0, timer.endDate.timeIntervalSinceNow)
            lastShownSecond = Int(left.rounded(.up))
            clock.remaining = left
        }
    }

    // MARK: Ticking

    private func startTicking() {
        // Checks four times a second so the end is caught promptly, but only
        // publishes when the displayed second changes — and never while the app
        // is in the background, where there's nothing on screen to update.
        ticker = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick(live: Bool = true) {
        guard let timer = active else { return }
        let left = timer.endDate.timeIntervalSinceNow
        if left <= 0 {
            finish(timer, live: live && left > -2)
        } else if UIApplication.shared.applicationState == .active {
            let shown = Int(left.rounded(.up))
            if shown != lastShownSecond {
                lastShownSecond = shown
                clock.remaining = left
            }
        }
    }

    private func finish(_ timer: ActiveTimer, live: Bool) {
        stopTicking()
        active = nil
        clock.remaining = 0
        finished = timer
        clearPersisted()

        // Put the Dismiss button where you'll see it when you open the app.
        AppRouter.shared.selectedTab = .timer

        let center = UNUserNotificationCenter.current()
        if live {
            // We caught the end ourselves (app open, or running in the background
            // on the silent audio): ring until dismissed, and cancel the backup.
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            startRinging()
            if UIApplication.shared.applicationState != .active {
                postSilentBanner(for: timer)   // a way back into the app from the lock screen
            }
        } else {
            // Opened the app after the end; the backup notification already rang.
            stopKeepAlive(releaseSession: true)
            if UIApplication.shared.applicationState == .active {
                center.removeDeliveredNotifications(withIdentifiers: [notificationID])
            }
        }
    }

    // MARK: Audio session + background keep-alive

    private func configureSession(duckOthers: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        // .playback ignores the silent switch. The silent loop mixes with other
        // audio so Google Maps keeps talking; the ring ducks it so you hear the ding.
        try session.setCategory(.playback, mode: .default,
                                options: duckOthers ? [.duckOthers] : [.mixWithOthers])
        try session.setActive(true)
    }

    private func startKeepAlive() {
        guard keepAlive?.isPlaying != true else { return }
        guard let url = Bundle.main.url(forResource: "Silence", withExtension: "wav") else {
            keepAliveOK = false
            return
        }
        do {
            try configureSession(duckOthers: false)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.prepareToPlay()
            keepAliveOK = player.play()
            keepAlive = player
        } catch {
            keepAlive = nil
            keepAliveOK = false
        }
    }

    private func stopKeepAlive(releaseSession: Bool) {
        keepAlive?.stop()
        keepAlive = nil
        if releaseSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// A phone call or Siri can pause our audio; pick it back up when the
    /// interruption ends so the app keeps running (and keeps ringing).
    private func observeAudioInterruptions() {
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                if self.isRinging {
                    self.ringPlayer?.play()
                } else if self.active != nil {
                    self.keepAlive = nil
                    self.startKeepAlive()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Ringing (until dismissed)

    private func startRinging() {
        guard !isRinging else { return }
        isRinging = true
        MaxVolume.shared.raiseToMax()

        if let url = Bundle.main.url(forResource: "RouteComplete", withExtension: "wav"),
           (try? configureSession(duckOthers: true)) != nil,
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1      // until dismissed
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            ringPlayer = player
        }
        // Only now let go of the silent loop, so audio never stops in between.
        stopKeepAlive(releaseSession: false)

        // A buzz with each ding, repeating until dismissed.
        ringTask = Task {
            while !Task.isCancelled {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                if ringPlayer == nil { AudioServicesPlaySystemSound(1007) }   // sound file couldn't play
                try? await Task.sleep(nanoseconds: 750_000_000)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(nanoseconds: 2_250_000_000)
            }
        }
    }

    private func stopRinging() {
        guard isRinging else { return }
        isRinging = false
        ringTask?.cancel()
        ringTask = nil
        ringPlayer?.stop()
        ringPlayer = nil
        MaxVolume.shared.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Notifications

    /// Backup for when iOS has closed the app: rings once, 2 s after the end.
    private func scheduleBackupNotification(for timer: ActiveTimer) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted, active?.id == timer.id else { return }
            let delay = timer.endDate.timeIntervalSinceNow + backupDelay
            guard delay > 0.5 else { return }

            let content = UNMutableNotificationContent()
            content.title = "Route complete"
            content.body = "\(timer.title) · \(timer.detail)"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("RouteComplete.wav"))

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Shown when the end arrives while the app is in the background: no sound
    /// (the app is already ringing), just a banner you can tap to get back in.
    private func postSilentBanner(for timer: ActiveTimer) {
        let content = UNMutableNotificationContent()
        content.title = "Route complete"
        content.body = "\(timer.title) is ringing. Open GeoMock and tap Dismiss."
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func removePendingNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
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
            active = saved
            lastShownSecond = Int(saved.endDate.timeIntervalSinceNow.rounded(.up))
            clock.remaining = saved.endDate.timeIntervalSinceNow
            startTicking()
            startKeepAlive()
            MaxVolume.shared.prepare()
        } else {
            finished = saved
            clearPersisted()
        }
    }
}
