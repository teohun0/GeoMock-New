//
//  TimerView.swift
//  The "Timer" tab. Tap a route and its countdown starts straight away (the
//  whole route at a fixed 100 km/h). When it ends the Route Complete alarm rings
//  on repeat until you press Stop Alarm (see RouteTimer.swift for how).
//

import SwiftUI

struct TimerView: View {
    @EnvironmentObject private var store: RouteTimerStore

    var body: some View {
        NavigationStack {
            Group {
                if let timer = store.active {
                    RunningTimerView(timer: timer,
                                     clock: store.clock,
                                     alertWarning: store.alertWarning,
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
            Section {
                ExpiryBannerView(boxed: false)
            }

            Section {
                ForEach(TimerRoute.all) { route in
                    Button {
                        store.start(title: route.title,
                                    detail: route.detail,
                                    duration: route.duration)
                    } label: {
                        HStack {
                            Text(route.title)
                                .font(.headline)
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
            }

            Section {
                Button("Test the ding (10 seconds)") {
                    store.start(title: "Ding test", detail: "10-second test", duration: 10)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Finished

    private func finishedView(_ done: ActiveTimer) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.orange)

            Text(done.completionTitle)
                .font(.title.bold())

            Text("\(done.title) · \(done.detail)")
                .foregroundStyle(.secondary)

            Text("Finished at \(done.endDate, style: .time)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("The alarm keeps ringing until you stop it.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                store.dismissFinished()
            } label: {
                Text("Stop Alarm")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
        .padding()
    }
}

// MARK: - Running (its own view so only this redraws as the clock ticks)

private struct RunningTimerView: View {
    let timer: ActiveTimer
    @ObservedObject var clock: TimerClock
    let alertWarning: String?
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
                Text("Ends at \(timer.endDate, style: .time)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                statusCaption
            }

            Spacer()

            Button {
                GoogleMapsLauncher.open()
            } label: {
                Label("Open Google Maps", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

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
        if let warning = alertWarning {
            Text(warning)
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else {
            Text("When it ends, the “\(timer.completionTitle)” alarm rings until you stop it here. With the app closed it rings through notifications for about 27 minutes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    TimerView()
        .environmentObject(RouteTimerStore())
        .environmentObject(AppExpiryStore())
        .environmentObject(AppRouter.shared)
}
