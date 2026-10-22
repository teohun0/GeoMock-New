//
//  ExpiryBannerView.swift
//  Shows the 7-day countdown and a button to start a fresh 7 days after the
//  app has been reinstalled from Xcode. Turns orange in the last day.
//  Big on purpose: the countdown is the one thing on the Home screen you
//  need to be able to read at a glance.
//

import SwiftUI
import Foundation

struct ExpiryBannerView: View {
    @EnvironmentObject private var expiry: AppExpiryStore
    @State private var confirmReset = false

    /// Draw its own rounded card. Turn off inside a List row, which already has one.
    var boxed = true

    var body: some View {
        let date = expiry.expiryDate
        let warn = expiry.isWarning
        let tint: Color = warn ? .orange : .secondary

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: warn ? "exclamationmark.triangle.fill" : "clock")
                    .font(.system(size: 40))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(date > Date() ? "Expires in" : "Expired")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Group {
                        if date > Date() {
                            Text(date, style: .relative)
                        } else {
                            Text("\(date, style: .relative) ago")
                        }
                    }
                    .font(.title.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Button {
                confirmReset = true
            } label: {
                Text("Reset 7-day timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(warn ? Color.orange : Color.accentColor)
            .confirmationDialog("Start a fresh 7 days?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset 7-day timer") {
                    Task { await expiry.resetTimer() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only do this after Xcode has reinstalled GeoMock. The reminder moves to a day before the new expiry.")
            }

            if expiry.notificationsDenied {
                Text("Notifications are off for GeoMock, so you won't get the reminder.")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        .padding(boxed ? 20 : 0)
        .background {
            if boxed {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
            }
        }
    }
}
