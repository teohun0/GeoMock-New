//
//  TimerView.swift
//  The "Timer" tab. Tap a route and the countdown starts straight away
//  (fixed 82 km/h). When it ends the phone rings and vibrates until you
//  tap Dismiss.
//

import SwiftUI

struct TimerView: View {
    @EnvironmentObject private var store: RouteTimerStore
    @EnvironmentObject private var expiry: AppExpiryStore

    var body: some View {
        NavigationStack {
            Group {
                if let timer = store.active {
                    RunningTimerView(timer: timer,
                                     clock: store.clock,
                                     keepAliveOK: store.keepAliveOK,
                                     onCancel: { store.cancel() })
                } else if let done = store.finished {
                    finishedView(done)
                } else {
                    pickerList
                }
            }
            .navigationTitle("Timer")
        }
    }

    // MARK: - Pick a route

    private var pickerList: some View {
        List {
            if expiry.expiryDate != nil {
                Section {
                    ExpiryBannerView(boxed: false)
                }
            }

            Section {
                ForEach(TimerRoute.all) { route in
                    Button {
                        store.start(title: route.title,
                                    detail: route.detail,
                                    duration: route.duration)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.title)
                                    .font(.headline)
                                Text(route.distanceLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(TimerFormat.clock(route.duration))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Start a route · \(Int(TimerRoute.speedKmh)) km/h").textCase(nil)
            } footer: {
                Text("Tap a route to start its timer straight away.")
            }

            Section {
                Button("Test the ding (10 seconds)") {
                    store.start(title: "Ding test", detail: "10-second test", duration: 10)
                }
            } footer: {
                Text("Lock the phone and flip the silent switch while it runs. It should ring until you tap Dismiss in the app.")
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Finished

    private func finishedView(_ done: ActiveTimer) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: store.isRinging ? "bell.fill" : "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(store.isRinging ? Color.orange : Color.green)

            Text("Route complete")
                .font(.title.bold())

            Text("\(done.title) · \(done.detail)")
                .foregroundStyle(.secondary)

            Text("Finished at \(done.endDate, style: .time)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if store.isRinging {
                Text("Ringing until you tap Dismiss.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.dismissFinished()
            } label: {
                Text("Dismiss")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

// MARK: - Running (its own view so only this redraws as the clock ticks)

private struct RunningTimerView: View {
    let timer: ActiveTimer
    @ObservedObject var clock: TimerClock
    let keepAliveOK: Bool?
    let onCancel: () -> Void

    var body: some View {
        let progress = timer.totalDuration > 0
            ? min(max(1 - clock.remaining / timer.totalDuration, 0), 1)
            : 1

        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 4) {
                Text(timer.title)
                    .font(.title2.bold())
                Text(timer.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(TimerFormat.clock(clock.remaining))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 260, height: 260)
            .padding(.vertical, 12)

            VStack(spacing: 4) {
                Text("Rings at \(timer.endDate, style: .time)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                statusCaption
            }

            Spacer()

            Button(role: .destructive, action: onCancel) {
                Text("Cancel Timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
    }

    @ViewBuilder
    private var statusCaption: some View {
        switch keepAliveOK {
        case .some(true):
            Text("Keeps running in the background. Don't swipe the app away.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        case .some(false):
            Text("Background audio didn't start, so the ring may not play with the phone locked. Stay on this screen.")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        case .none:
            EmptyView()
        }
    }
}

#Preview {
    TimerView()
        .environmentObject(RouteTimerStore())
        .environmentObject(AppExpiryStore())
        .environmentObject(AppRouter.shared)
}
