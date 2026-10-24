//
//  TutorialView.swift
//  A paginated walkthrough of the actual Xcode menu path for loading a
//  GPX file — not the in-app simulator, this is specifically the
//  system-wide Debug > Simulate Location workflow. Swipe between steps.
//

import SwiftUI

private let tutorialSteps: [GuideStep] = [
    GuideStep(
        title: "Find the Debug menu",
        detail: "On your Mac, look at the very top of the screen — Xcode's menu bar. Click Debug.",
        symbol: "menubar.rectangle"
    ),
    GuideStep(
        title: "Open Simulate Location",
        detail: "In the Debug menu, look for \"Simulate Location\" and hover over it — a submenu opens to the side.",
        symbol: "location.circle"
    ),
    GuideStep(
        title: "Don't see your file listed?",
        detail: "If nothing shows up there yet, look for \"Add GPX File to Workspace…\" in that same submenu instead.",
        symbol: "doc.badge.plus"
    ),
    GuideStep(
        title: "Pick your GPX file",
        detail: "Browse to the .gpx file you want to mock and select it. From now on, it'll appear in the Simulate Location list, ready to pick anytime your app is running.",
        symbol: "checkmark.seal"
    ),
]

struct TutorialView: View {
    @State private var isComplete = false

    var body: some View {
        Group {
            if isComplete {
                completionView
            } else {
                GuidePager(steps: tutorialSteps, finishTitle: "Finish") {
                    isComplete = true
                }
            }
        }
        .navigationTitle("Tutorial")
        .navigationBarBackButtonHidden(isComplete)
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You have completed the tutorial")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    GoogleMapsLauncher.open()
                } label: {
                    Text("Open Google Maps")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isComplete = false   // the pager is rebuilt, so it starts at step 1 again
                } label: {
                    Text("Retake Tutorial")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        TutorialView()
    }
}
