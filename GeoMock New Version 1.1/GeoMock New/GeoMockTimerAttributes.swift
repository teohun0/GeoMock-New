//
//  GeoMockTimerAttributes.swift
//  What the Live Activity (lock screen + Dynamic Island) needs to know about a
//  running route timer. This file must belong to BOTH targets: "GeoMock New"
//  and the Live Activity widget extension (File Inspector > Target Membership),
//  because the app starts the activity and the extension draws it.
//
//  The countdown itself is drawn by the system from startDate...endDate, so it
//  keeps ticking with the app closed and no updates have to be sent.
//

import ActivityKit
import Foundation

nonisolated struct GeoMockTimerAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// True once the route timer has run out (the activity then reads "Route complete").
        var isFinished = false
    }

    let routeTitle: String
    let detail: String
    let startDate: Date
    let endDate: Date
}
