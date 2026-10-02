//
//  HelpView.swift
//  In-app instructions covering both mocking paths: the self-contained
//  in-app simulator, and the GPX-via-Xcode workflow for system-wide testing.
//

import SwiftUI

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct HelpView: View {
    var body: some View {
        List {
            Section {
                Text("Two ways to mock location: entirely inside this app (no computer needed), or system-wide through Xcode (needs a Mac, but reaches other apps too, like Google Maps).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Quick Start — In-App Routes") {
                StepRow(number: 1, text: "Open the app — the Routes screen lists saved routes, starting with a built-in demo.")
                StepRow(number: 2, text: "Tap any route in the list to start following it immediately.")
                StepRow(number: 3, text: "Live coordinates and speed update at the top of the screen while it runs.")
                StepRow(number: 4, text: "Tap Stop on that status card to end the simulation.")
                StepRow(number: 5, text: "This never leaves the app — other apps like Maps won't see it, by design. That's normal, not a bug.")
            }

            Section("Load a GPX File via Xcode (Reaches Other Apps)") {
                StepRow(number: 1, text: "Connect your iPhone to your Mac and open this project in Xcode.")
                StepRow(number: 2, text: "In Xcode's Project Navigator (the file list on the left), right-click your app's folder → \"Add Files to [project name]...\"")
                StepRow(number: 3, text: "Browse to your .gpx file, select it, make sure \"Copy items if needed\" is checked, then Add. It now sits inside the Xcode file structure alongside your other source files.")
                StepRow(number: 4, text: "Pick your iPhone from the device dropdown next to the Run button in Xcode's top toolbar, then press ⌘R to build and run on it.")
                StepRow(number: 5, text: "While the app is running: open Xcode's Debug menu (top menu bar of Xcode itself, not inside this app) → Simulate Location. Your GPX file's name appears in that list, pulled directly from what you added in step 3 — tap it to start playback.")
                StepRow(number: 6, text: "To have it load automatically every run instead of picking it manually: Product → Scheme → Edit Scheme → Run tab → Options → check \"Allow Location Simulation\" → choose your file from the Default Location dropdown — it's the same file list from step 3.")
            }

            Section("Bridge to Other Apps (Google Maps, etc.)") {
                StepRow(number: 1, text: "On the Routes screen, turn on \"Bridge to other apps.\"")
                StepRow(number: 2, text: "Allow the location permission prompt the first time it appears.")
                StepRow(number: 3, text: "Keep this app running and Xcode's debug session connected the whole time — disconnecting or stopping the session reverts everything to real GPS instantly.")
                StepRow(number: 4, text: "Switch to Google Maps (or any other app) — it should now track the same simulated position from step above.")
            }

            Section("Route Timer (Timer Tab)") {
                StepRow(number: 1, text: "Open the Timer tab. Each route shows how long it takes at 82 km/h.")
                StepRow(number: 2, text: "Tap a route the moment you start it. The countdown begins immediately, and Cancel Timer stops it right away.")
                StepRow(number: 3, text: "At zero the phone rings and vibrates until you tap Dismiss in the app, even in silent mode or Focus. GeoMock keeps itself running in the background during a timer, so don't swipe it away.")
                StepRow(number: 4, text: "Use \"Test the ding\" to try it in 10 seconds.")
            }

            Section("Build Your Own Route") {
                StepRow(number: 1, text: "From the Routes screen, tap \"New Route\" in the top-right.")
                StepRow(number: 2, text: "Tap anywhere on the map to drop a waypoint — repeat to build out a path.")
                StepRow(number: 3, text: "Tap \"Start Simulating\" to preview it immediately, right there on the map.")
                StepRow(number: 4, text: "Tap \"Save to Library\" to name it and add it to the main Routes list, or \"Generate GPX to share\" to export it for the Xcode workflow above instead.")
            }
        }
        .navigationTitle("How to Use")
        .listStyle(.insetGrouped)
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
