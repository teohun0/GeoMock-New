//
//  JourneyProgressView.swift
//  The "Progress" tab. Shows how far along one of the bundled GPX routes the phone
//  currently is, using the live location (real GPS, or the simulated position while
//  Xcode's Debug > Simulate Location plays a GPX file). The maths is in JourneyTracker.
//

import SwiftUI
import UIKit

struct JourneyProgressView: View {
    @EnvironmentObject private var tracker: JourneyTracker

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Route", selection: $tracker.mode) {
                        Text("Auto").tag(JourneyTracker.Mode.auto)
                        ForEach(TimerRoute.all) { route in
                            Text(route.title).tag(JourneyTracker.Mode.route(route.id))
                        }
                    }
                    .pickerStyle(.segmented)

                    content
                }
                .padding()
            }
            .navigationTitle("Progress")
        }
        .onAppear { tracker.startOnce() }
    }

    // MARK: - What to show

    @ViewBuilder
    private var content: some View {
        if let problem = tracker.routeFilesProblem {
            notice(problem, symbol: "exclamationmark.triangle.fill", tint: .orange)
        }

        if !tracker.hasRoutes {
            EmptyView()
        } else if tracker.authorization == .notDetermined {
            VStack(spacing: 16) {
                notice("GeoMock needs your location to work out how far along a route you are.",
                       symbol: "location.circle",
                       tint: Color.accentColor)
                Button {
                    tracker.start()
                } label: {
                    Label("Allow Location", systemImage: "location")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else if tracker.authorization == .denied || tracker.authorization == .restricted {
            VStack(spacing: 16) {
                notice("Location is off for GeoMock. Turn it on in Settings > Privacy & Security > Location Services > GeoMock New.",
                       symbol: "location.slash",
                       tint: .orange)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else if let snap = tracker.snapshot {
            snapshotView(snap)
            controls
        } else {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(tracker.isTracking ? "Waiting for a location fix…" : "Tracking is paused.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 40)
            controls
        }
    }

    // MARK: - Progress

    private func snapshotView(_ s: JourneyTracker.Snapshot) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text(s.routeTitle)
                    .font(.title2.bold())
                Spacer()
                statusChip(s.state)
            }

            if s.state == .notNearRoute {
                notice("You're \(distanceText(s.offRouteMeters)) from the nearest route (\(s.routeTitle)). Progress shows once you're within \(distanceText(1500)) of it.",
                       symbol: "location.slash",
                       tint: .secondary)
                statsCard(rows: [
                    ("Speed", speedText(s.speedKmh)),
                    ("Last update", s.fixDate.formatted(date: .omitted, time: .standard)),
                ])
            } else {
                Text(s.fraction, format: .percent.precision(.fractionLength(1)))
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                progressBar(s)

                statsCard(rows: statRows(for: s))

                if let other = s.alsoMatches {
                    notice("This spot is on \(other) too, so GeoMock can't tell which one you're on yet. Pick a route above to lock it in; otherwise it settles by itself where the two routes split.",
                           symbol: "arrow.triangle.branch",
                           tint: .orange)
                }
            }
        }
    }

    private func statRows(for s: JourneyTracker.Snapshot) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Covered", distanceText(s.alongMeters)),
            ("Remaining", distanceText(s.remainingMeters)),
        ]
        rows.append(("Off route", distanceText(s.offRouteMeters)))
        rows.append(("Speed", speedText(s.speedKmh)))
        rows.append(("Arrives about", s.etaDate?.formatted(date: .omitted, time: .shortened) ?? "–"))
        rows.append(("Last update", s.fixDate.formatted(date: .omitted, time: .standard)))
        return rows
    }

    private func progressBar(_ s: JourneyTracker.Snapshot) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: width * s.fraction)
                }
                .clipShape(Capsule())
            }
            .frame(height: 18)

            HStack {
                Text("Start")
                Spacer()
                Text("Finish · \(distanceText(s.lengthMeters))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func statsCard(rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(rows[i].1)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 12)
                if i < rows.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                tracker.resetProgress()
            } label: {
                Label("Reset progress", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                if tracker.isTracking { tracker.stop() } else { tracker.start() }
            } label: {
                Label(tracker.isTracking ? "Pause tracking" : "Resume tracking",
                      systemImage: tracker.isTracking ? "pause.circle" : "play.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Tracking runs while GeoMock is open. It follows the real location, or the simulated one while Xcode is playing a GPX file (Debug > Simulate Location). Use Reset progress before replaying a route.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Pieces

    private func statusChip(_ state: JourneyTracker.Snapshot.State) -> some View {
        let (label, symbol, tint): (String, String, Color) = {
            switch state {
            case .atStart:      return ("At the start", "flag", Color.accentColor)
            case .onRoute:      return ("On route", "checkmark.circle.fill", Color.green)
            case .offRoute:     return ("Off route", "exclamationmark.triangle.fill", Color.orange)
            case .finished:     return ("Finished", "flag.checkered", Color.green)
            case .notNearRoute: return ("Not on a route", "location.slash", Color.secondary)
            }
        }()
        return Label(label, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private func notice(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        }
    }

    private func distanceText(_ metres: Double) -> String {
        metres < 1000
            ? "\(Int(metres.rounded())) m"
            : String(format: "%.1f km", metres / 1000)
    }

    private func speedText(_ kmh: Double?) -> String {
        guard let kmh else { return "–" }
        return "\(Int(kmh.rounded())) km/h"
    }
}

#Preview {
    JourneyProgressView()
        .environmentObject(JourneyTracker())
}
