//
//  WelcomeView.swift
//  Home tab: logo, tutorial, Google Maps shortcut and the expiry banner.
//  The two buttons use the same large size as the buttons on a running timer
//  (Timer tab), and span the same width.
//

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // The logo's own rounded corners sit on a light backdrop in the JPEG,
                // so clip to the same curve (22.3% of the width) to hide it.
                Image("GeoMockLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 120 * 0.23, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    .accessibilityLabel("GeoMock")

                Text("Welcome to GeoMock")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                ExpiryBannerView()

                Spacer()

                VStack(spacing: 20) {
                    NavigationLink {
                        TutorialView()
                    } label: {
                        Label("Tutorial", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        GoogleMapsLauncher.open()
                    } label: {
                        Label("Open Google Maps", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AppExpiryStore())
        .environmentObject(AppRouter.shared)
}
