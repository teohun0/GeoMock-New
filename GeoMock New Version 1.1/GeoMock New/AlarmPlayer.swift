//
//  AlarmPlayer.swift
//  The in-app half of the route-complete alarm: plays RouteComplete.wav on an
//  endless loop until stop() is called.
//
//  iOS cuts a notification sound off at 30 seconds, so a notification alone can
//  never ring "until you stop it". While GeoMock is open it makes the sound
//  itself instead: an AVAudioPlayer with numberOfLoops = -1 under the .playback
//  audio category. Like the Clock app, that is not muted by the silent switch or
//  by a Focus. It plays at whatever media volume the phone is set to.
//
//  The session is "mix with others" (and ducks them) on purpose. A normal session
//  has to interrupt other audio to activate, and iOS refuses that unless the app is
//  fully in the foreground (error '!int', "Session activation failed"), which is
//  exactly the situation when you open the app from a notification while Maps or
//  music is playing. Mixing is always allowed, and ducking turns the other audio down.
//
//  The "audio" background mode already in Info.plist keeps it ringing if you
//  lock the phone or switch to another app while it plays.
//
//  Threading: AVAudioSession.setActive is a blocking request to the system audio
//  server. It usually answers in a few milliseconds, but it can wait much longer
//  (another app holding the audio, a Bluetooth or car connection changing route),
//  and on the main thread that freezes the screen. So activating and deactivating
//  the session happens on a background queue, and start() reports back later
//  through its completion handler instead of returning straight away.
//

import AVFoundation
import Combine

final class AlarmPlayer {
    static let shared = AlarmPlayer()

    private var player: AVAudioPlayer?
    /// True from start() until stop(), even if the system has paused the sound for a moment.
    private var shouldRing = false
    /// True while the audio session is being activated in the background.
    private var isStarting = false
    /// Everyone who called start() while it was still in progress, answered together at the end.
    private var pendingStarts: [(Bool) -> Void] = []
    private var cancellables = Set<AnyCancellable>()

    /// All audio session activation and deactivation goes through this one serial queue,
    /// so a stop can never overtake the start before it.
    private let sessionQueue = DispatchQueue(label: "geomock.alarm.audio-session", qos: .userInitiated)

    private init() {
        // A phone call, Siri or another app can interrupt the audio. When that ends, ring again.
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleInterruption(note) }
            .store(in: &cancellables)
    }

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Starts the endless loop. `completion` is called on the main thread with true once the
    /// sound is playing, or false if iOS refused (so the caller can leave the notification
    /// alarm in place as the fallback).
    func start(completion: ((Bool) -> Void)? = nil) {
        if isPlaying {
            completion?(true)
            return
        }
        if let completion { pendingStarts.append(completion) }
        shouldRing = true
        guard !isStarting else { return }
        isStarting = true

        sessionQueue.async { [weak self] in
            let failure: String?
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
                try session.setActive(true)
                failure = nil
            } catch {
                failure = String(describing: error)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated { self.finishStart(failure: failure) }
            }
        }
    }

    /// Ends the loop for good.
    func stop() {
        guard shouldRing || player != nil else { return }
        shouldRing = false
        player?.stop()
        player = nil
        deactivateSession()
    }

    // MARK: Private

    /// Runs on the main thread once the audio session has been activated (or has failed to be).
    private func finishStart(failure: String?) {
        isStarting = false
        var started = false

        if let failure {
            // Expected whenever the app isn't on screen: iOS won't let an app start audio from the
            // background. The notification chain covers that, and the loop starts when you open the app.
            NSLog("AlarmPlayer could not start (normal if the app isn't on screen): %@", failure)
        } else if !shouldRing {
            // Stop was pressed while the session was still being activated. Nothing to play.
        } else if let url = Bundle.main.url(forResource: "RouteComplete", withExtension: "wav") {
            do {
                let newPlayer = try AVAudioPlayer(contentsOf: url)
                newPlayer.numberOfLoops = -1        // forever
                newPlayer.volume = 1.0
                newPlayer.prepareToPlay()
                if newPlayer.play() {
                    player = newPlayer
                    started = true
                }
            } catch {
                NSLog("AlarmPlayer could not play: %@", String(describing: error))
            }
        } else {
            NSLog("AlarmPlayer: RouteComplete.wav is missing from the app bundle")
        }

        if !started {
            shouldRing = false
            // If the session did activate, let go of it again.
            if failure == nil { deactivateSession() }
        }

        let callbacks = pendingStarts
        pendingStarts = []
        for callback in callbacks { callback(started) }
    }

    /// Lets music or a podcast that was ducked or paused for the alarm carry on.
    private func deactivateSession() {
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard shouldRing,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        // Start from scratch: the old player is paused and the audio session was deactivated.
        player = nil
        start()
    }
}
