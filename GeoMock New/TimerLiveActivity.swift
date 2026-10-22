//
//  TimerLiveActivity.swift
//  Starts, resumes and ends the Live Activity that shows the time left on the
//  lock screen and in the Dynamic Island (iPhone 14 Pro and later; other
//  iPhones show it on the lock screen only).
//
//  It needs the Live Activity widget extension target to draw it. Without that
//  target the app still runs normally; the request just has nothing to show.
//
//  The activity goes stale at the route's end time (the system does that by
//  itself, even with the app suspended), at which point it reads "Route
//  complete". It's removed when you open the app after the end, or cancel.
//

import ActivityKit
import Foundation

final class TimerLiveActivityController {
    static let shared = TimerLiveActivityController()

    /// Bumped by every start/end so a slow earlier request can't outlive a later cancel.
    private var generation = 0

    private init() {}

    /// Replaces any running activity with one for this timer.
    func start(for timer: ActiveTimer) {
        generation += 1
        let mine = generation
        Task {
            await endAll(finalState: nil, dismissal: .immediate)
            guard mine == generation else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = GeoMockTimerAttributes(routeTitle: timer.title,
                                                    detail: timer.detail,
                                                    startDate: timer.startDate,
                                                    endDate: timer.endDate)
            let content = ActivityContent(state: GeoMockTimerAttributes.ContentState(),
                                          staleDate: timer.endDate)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                NSLog("Live Activity could not start: %@", String(describing: error))
            }
        }
    }

    /// After the app relaunches mid-route: keep the activity that's already running, or start one.
    func resume(for timer: ActiveTimer) {
        let alreadyRunning = Activity<GeoMockTimerAttributes>.activities.contains {
            $0.attributes.endDate == timer.endDate
        }
        if !alreadyRunning { start(for: timer) }
    }

    /// Ends the activity: straight away when cancelled, after a couple of minutes on "Route complete" when it ran out.
    func end(finished: Bool) {
        generation += 1
        Task {
            if finished {
                await endAll(finalState: GeoMockTimerAttributes.ContentState(isFinished: true),
                             dismissal: .after(Date().addingTimeInterval(120)))
            } else {
                await endAll(finalState: nil, dismissal: .immediate)
            }
        }
    }

    private func endAll(finalState: GeoMockTimerAttributes.ContentState?,
                        dismissal: ActivityUIDismissalPolicy) async {
        for activity in Activity<GeoMockTimerAttributes>.activities {
            if let finalState {
                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: dismissal)
            } else {
                await activity.end(nil, dismissalPolicy: dismissal)
            }
        }
    }
}
