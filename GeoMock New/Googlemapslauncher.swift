//
//  GoogleMapsLauncher.swift
//  Opens the Google Maps app directly if installed, otherwise falls back
//  to the web version so the button always does something useful.
//
//  Requires an Info.plist entry for canOpenURL to correctly detect the
//  app (see setup note below) — without it, canOpenURL always returns
//  false and this silently falls through to the web link every time.
//

import UIKit

enum GoogleMapsLauncher {
    static func open() {
        if let appURL = URL(string: "comgooglemaps://"), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = URL(string: "https://www.google.com/maps") {
            UIApplication.shared.open(webURL)
        }
    }
}
