//
//  MaxVolume.swift
//  iOS has no official way for an app to set the system volume. The usual
//  workaround is a hidden MPVolumeView: its slider can be moved from code.
//  The route-complete ring uses it to push the media volume to maximum, and
//  puts it back when the ring is dismissed.
//
//  Best effort: the slider needs the view to be in a window, so it is added
//  when a timer starts (app in the foreground). Whether iOS lets the slider
//  move while the app is in the background is not guaranteed.
//

import UIKit
import MediaPlayer
import AVFoundation

final class MaxVolume {
    static let shared = MaxVolume()

    private let volumeView = MPVolumeView(frame: CGRect(x: -3000, y: -3000, width: 10, height: 10))
    private var savedVolume: Float?

    private init() {}

    /// Call while the app is on screen so the hidden view is already in a window.
    func prepare() {
        attachIfNeeded()
    }

    func raiseToMax() {
        attachIfNeeded()
        if savedVolume == nil {
            savedVolume = AVAudioSession.sharedInstance().outputVolume
        }
        setVolume(1.0)
    }

    func restore() {
        guard let previous = savedVolume else { return }
        savedVolume = nil
        // A reading of exactly 0 is more likely a bad read than a muted phone.
        if previous > 0.02 {
            setVolume(previous)
        }
    }

    private func attachIfNeeded() {
        guard volumeView.superview == nil else { return }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return }
        volumeView.alpha = 0.01
        window.addSubview(volumeView)
    }

    private func setVolume(_ value: Float) {
        // The slider appears a moment after the view joins a window.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            volumeView.subviews.compactMap { $0 as? UISlider }.first?.value = value
        }
    }
}
