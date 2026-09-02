//
//  RootTabView.swift
//  App root: the existing launch screen on one tab, the route Timer on
//  the other. The stores live here (not inside individual views) so a
//  running countdown keeps ticking while you're on the other tab, and so
//  the expiry banner and re-attach guide work from anywhere.
//

import SwiftUI

struct RootTabView: View {
    @StateObject private var timerStore = RouteTimerStore()
    @StateObject private var expiryStore = AppExpiryStore()
    @StateObject private var connection = MacConnectionMonitor()
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
        }
        .sheet(isPresented: $router.showReattachGuide) {
            ReattachGuideView(expiry: expiryStore)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                timerStore.refresh()
                expiryStore.refresh()
                connection.evaluate()
            }
        }
        // Last on purpose: environment only flows to what sits inside the modifier.
        .environmentObject(timerStore)
        .environmentObject(expiryStore)
        .environmentObject(router)
    }
}

#Preview {
    RootTabView()
}
