//
//  GoogleMapsLauncher.swift
//  Opens the Google Maps app directly if installed, otherwise falls back
//  to the web version so the button always does something useful.
//
//  It makes a single openURL call for the app and only tries the web page if
//  iOS reports that the app could not be opened (no separate canOpenURL check
//  beforehand). Note: while GeoMock is run from Xcode, iOS may print
//  "sandbox_extension_issue_file failed for (null)" / "unable to make sandbox
//  extension" in the console when handing off to another app. Those lines come
//  from the system's app-switch, not from this code, and don't stop Maps opening.
//

import UIKit

enum GoogleMapsLauncher {
    static func open() {
        guard let appURL = URL(string: "comgooglemaps://"),
              let webURL = URL(string: "https://www.google.com/maps") else { return }
        UIApplication.shared.open(appURL, options: [:]) { opened in
            if !opened {
                UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
            }
        }
    }
}
