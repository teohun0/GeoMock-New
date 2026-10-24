//
//  GeoMock_NewApp.swift
//  GeoMock New
//
//  Created by Teo Mong Kwang on 1/9/26.
//

import SwiftUI

/// TEMPORARY crash finder. If the app dies on an uncaught exception, this prints
/// the function names of the stack (the plain crash log only shows addresses).
/// Delete it, and the line in init(), once the crash is fixed.
nonisolated func logUncaughtException(_ exception: NSException) {
    NSLog("UNCAUGHT EXCEPTION: %@ - %@", exception.name.rawValue, exception.reason ?? "")
    NSLog("STACK:\n%@", exception.callStackSymbols.joined(separator: "\n"))
}

@main
struct GeoMock_NewApp: App {
    init() {
        NSSetUncaughtExceptionHandler(logUncaughtException)
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
