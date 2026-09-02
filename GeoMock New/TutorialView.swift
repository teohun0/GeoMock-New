//
//  TutorialView.swift
//  A paginated walkthrough of the actual Xcode menu path for loading a
//  GPX file — not the in-app simulator, this is specifically the
//  system-wide Debug > Simulate Location workflow.
//

import SwiftUI

private struct TutorialStep {
    let title: String
    let detail: String
    let symbol: String
}

private let tutorialSteps: [TutorialStep] = [
    TutorialStep(
        title: "Find the Debug menu",
        detail: "On your Mac, look at the very top of the screen — Xcode's menu bar. Click Debug.",
        symbol: "menubar.rectangle"
    ),
    TutorialStep(
        title: "Open Simulate Location",
        detail: "In the Debug menu, look for \"Simulate Location\" and hover over it — a submenu opens to the side.",
        symbol: "location.circle"
    ),
    TutorialStep(
        title: "Don't see your file listed?",
        detail: "If nothing shows up there yet, look for \"Add GPX File to Workspace…\" in that same submenu instead.",
        symbol: "doc.badge.plus"
    ),
    TutorialStep(
        title: "Pick your GPX file",
        detail: "Browse to the .gpx file you want to mock and select it. From now on, it'll appear in the Simulate Location list, ready to pick anytime your app is running.",
        symbol: "checkmark.seal"
    ),
]

struct TutorialView: View {
    @State private var stepIndex = 0
    @State private var isComplete = false

    var body: some View {
        Group {
            if isComplete {
                completionView
            } else {
                stepView
            }
        }
        .navigationTitle("Tutorial")
        .navigationBarBackButtonHidden(isComplete)
    }

    private var stepView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: tutorialSteps[stepIndex].symbol)
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text(tutorialSteps[stepIndex].title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(tutorialSteps[stepIndex].detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 6) {
                ForEach(tutorialSteps.indices, id: \.self) { i in
                    Circle()
                        .fill(i == stepIndex ? Color.accentColor : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                }
            }

            HStack {
                Button("Back") {
                    stepIndex = max(0, stepIndex - 1)
                }
                .disabled(stepIndex == 0)

                Spacer()

                Button(stepIndex == tutorialSteps.count - 1 ? "Finish" : "Next") {
                    if stepIndex == tutorialSteps.count - 1 {
                        isComplete = true
                    } else {
                        stepIndex += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 32)
            .padding(.bottom)
        }
        .padding(.top)
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
                    stepIndex = 0
                    isComplete = false
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
