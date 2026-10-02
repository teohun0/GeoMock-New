//
//  MacConnectionMonitor.swift
//  iOS can't tell an app whether the phone is cabled to a computer, so this
//  uses two signals together:
//    • a debugger (Xcode) is attached to the app, and
//    • the phone is charging (or full while plugged in).
//  Both true = running from your Mac on a cable. When that becomes true
//  (at launch, or when you plug in) the app jumps to the Timer tab once.
//  It doesn't keep pulling you back, so you can still visit other tabs.
//

import UIKit
import Combine

final class MacConnectionMonitor: ObservableObject {
    private var wasConnected = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        NotificationCenter.default
            .publisher(for: UIDevice.batteryStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        // The battery state can read "unknown" for a moment right after
        // monitoring starts, so check once more shortly after launch.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self?.evaluate()
        }
    }

    /// Call at launch and whenever the app comes to the foreground.
    func evaluate() {
        let connected = Self.debuggerAttached && Self.isPluggedIn
        defer { wasConnected = connected }

        if connected && !wasConnected {
            AppRouter.shared.selectedTab = .timer
        }
    }

    private static var isPluggedIn: Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    /// True when Xcode (or any debugger) is attached to this process.
    private static var debuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
