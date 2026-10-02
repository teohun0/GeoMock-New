//
//  GeoMock_NewApp.swift
//  GeoMock New
//
//  Created by Teo Mong Kwang on 1/9/26.
//

import SwiftUI

@main
struct GeoMock_NewApp: App {
    init() {
        NotificationRouter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
