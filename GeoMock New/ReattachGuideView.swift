//
//  ReattachGuideView.swift
//  Walkthrough for renewing GeoMock from your Mac when its install is about
//  to expire (or already has). Same paginated style as TutorialView, shown
//  in a sheet from the expiry banner and from expiry notifications.
//

import SwiftUI

private struct ReattachStep {
    let title: String
    let detail: String
    let symbol: String
}

private let reattachSteps: [ReattachStep] = [
    ReattachStep(
        title: "Why this is needed",
        detail: "Apps installed from Xcode stop opening when their signing runs out — 7 days with a free Apple ID. Running GeoMock from Xcode again renews it.",
        symbol: "clock.badge.exclamationmark"
    ),
    ReattachStep(
        title: "Plug in your iPhone",
        detail: "Connect your iPhone to your Mac with a cable and unlock it. Tap \"Trust This Computer\" if it asks.",
        symbol: "cable.connector"
    ),
    ReattachStep(
        title: "Open the project, pick your iPhone",
        detail: "Open the GeoMock project in Xcode. At the top of the window, click the device menu next to the app name and choose your iPhone under iOS Devices.",
        symbol: "iphone"
    ),
    ReattachStep(
        title: "Press Run",
        detail: "Click the ▶ Run button, or press ⌘R. Xcode rebuilds GeoMock and installs it on your phone, which restarts the expiry clock. This works even if the app has already expired.",
        symbol: "play.fill"
    ),
    ReattachStep(
        title: "If it won't open",
        detail: "On your iPhone, go to Settings → General → VPN & Device Management, tap your Apple ID and choose Trust. If asked, also turn on Developer Mode in Settings → Privacy & Security.",
        symbol: "exclamationmark.shield"
    ),
    ReattachStep(
        title: "Check the new date",
        detail: "Open GeoMock and look at the banner on the Home or Timer tab — it shows the new expiry date. You'll get fresh reminders before that date too.",
        symbol: "checkmark.seal"
    ),
]

struct ReattachGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0

    private var isLastStep: Bool { stepIndex == reattachSteps.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: reattachSteps[stepIndex].symbol)
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text(reattachSteps[stepIndex].title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(reattachSteps[stepIndex].detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(reattachSteps.indices, id: \.self) { i in
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

                    Button(isLastStep ? "Done" : "Next") {
                        if isLastStep {
                            dismiss()
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
            .navigationTitle("Re-attach from Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ReattachGuideView()
}
