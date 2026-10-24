//
//  RootTabView.swift
//  App root: the existing launch screen on one tab, the route Timer on
//  the next, and the journey Progress tracker on the third. The stores live
//  here (not inside individual views) so a running countdown keeps ticking
//  while you're on another tab, the expiry banner works from anywhere, and the
//  tracker keeps its place along the route when you switch tabs.
//

import SwiftUI

struct RootTabView: View {
    @StateObject private var timerStore = RouteTimerStore()
    @StateObject private var expiryStore = AppExpiryStore()
    @StateObject private var connection = MacConnectionMonitor()
    @StateObject private var journey = JourneyTracker()
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.selectedTab) {
            WelcomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            TimerView()
                .tabItem { Label("Timer", systemImage: "timer") }
                .tag(AppTab.timer)

            JourneyProgressView()
                .tabItem { Label("Progress", systemImage: "location.circle") }
                .tag(AppTab.progress)
        }
        // onChange below doesn't fire for the very first scene phase, so this catches a launch while
        // an alarm is still ringing (the in-app loop is started here once the app is really on screen).
        .onAppear { timerStore.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                timerStore.refresh()
                expiryStore.refresh()
                connection.evaluate()
                journey.resumeIfNeeded()
            }
        }
        // Last on purpose: environment only flows to what sits inside the modifier.
        .environmentObject(timerStore)
        .environmentObject(expiryStore)
        .environmentObject(journey)
        .environmentObject(router)
    }
}

#Preview {
    RootTabView()
}
