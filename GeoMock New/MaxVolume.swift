//
//  MaxVolume.swift
//  iOS has no official way for an app to set the system volume. The usual
//  workaround is a hidden MPVolumeView: its slider can be moved from code.
//  The route-complete ring uses it to push the media volume to maximum, and
//  puts it back when the ring is dismissed.
//
//  The view only exists while a timer is running or ringing — it is created
//  when needed and thrown away afterwards, so it costs nothing the rest of the time.
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

    private var volumeView: MPVolumeView?
    private var savedVolume: Float?

    private init() {}

    /// Call while the app is on screen so the hidden view is already in a window.
    func prepare() {
        _ = attachedView()
    }

    func raiseToMax() {
        if savedVolume == nil {
            savedVolume = AVAudioSession.sharedInstance().outputVolume
        }
        setVolume(1.0)
    }

    /// Puts the volume back (if it was raised) and discards the hidden view.
    func restoreAndRelease() {
        if let previous = savedVolume, previous > 0.02 {   // a reading of 0 is more likely a bad read than a muted phone
            setVolume(previous)
        }
        savedVolume = nil
        release(after: 0.5)
    }

    /// Discards the hidden view without touching the volume.
    func release(after delay: TimeInterval = 0) {
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            // A new timer may have started during the delay and wants the view back.
            guard savedVolume == nil else { return }
            volumeView?.removeFromSuperview()
            volumeView = nil
        }
    }

    private func attachedView() -> MPVolumeView? {
        if let existing = volumeView, existing.superview != nil { return existing }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return volumeView }
        let view = volumeView ?? MPVolumeView(frame: CGRect(x: -3000, y: -3000, width: 10, height: 10))
        view.alpha = 0.01
        window.addSubview(view)
        volumeView = view
        return view
    }

    private func setVolume(_ value: Float) {
        guard let view = attachedView() else { return }
        // The slider appears a moment after the view joins a window.
        Task { @MainActor [weak view] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            view?.subviews.compactMap { $0 as? UISlider }.first?.value = value
        }
    }
}
