//
//  ExpiryBannerView.swift
//  Shows when this install expires and offers the re-attach guide.
//  Turns orange inside the last two days.
//

import SwiftUI
import Foundation

struct ExpiryBannerView: View {
    @EnvironmentObject private var expiry: AppExpiryStore
    @EnvironmentObject private var router: AppRouter

    /// Draw its own rounded card. Turn off inside a List row, which already has one.
    var boxed = true
    /// When the build has no expiry date (Simulator, TestFlight), still show a
    /// small link to the guide instead of nothing.
    var showWhenUnknown = false

    var body: some View {
        if let date = expiry.expiryDate {
            let warn = expiry.isWarning

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: warn ? "exclamationmark.triangle.fill" : "clock")
                        .foregroundStyle(warn ? Color.orange : Color.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if date > Date() {
                                Text("Expires in \(date, style: .relative)")
                            } else {
                                Text("Expired \(date, style: .relative) ago")
                            }
                        }
                        .font(.subheadline.weight(.semibold))

                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Button {
                    router.showReattachGuide = true
                } label: {
                    Text("Review re-attach steps")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(warn ? Color.orange : Color.accentColor)

                if expiry.notificationsDenied {
                    Text("Notifications are off for GeoMock, so you won't get expiry reminders.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(boxed ? 14 : 0)
            .background {
                if boxed {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                }
            }
        } else if showWhenUnknown {
            Button("Re-attach from Mac") {
                router.showReattachGuide = true
            }
            .font(.footnote)
        }
    }
}
