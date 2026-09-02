//
//  WelcomeView.swift
//  Launch screen. Set this (not ContentView) as the root view in your
//  @main App file's WindowGroup to make it what actually appears on launch.
//

import SwiftUI

struct WelcomeView: View {
    @State private var showRoutes = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Welcome to GeoMock")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Spacer()

                VStack(spacing: 14) {
                    NavigationLink {
                        TutorialView()
                    } label: {
                        Text("Tutorial")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        GoogleMapsLauncher.open()
                    } label: {
                        Text("Open Google Maps")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 32)

                Button("View saved routes") {
                    showRoutes = true
                }
                .font(.footnote)
                .padding(.top, 4)

                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showRoutes) {
            ContentView()
        }
    }
}

#Preview {
    WelcomeView()
}
