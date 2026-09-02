//
//  RegionLockSimulationTests.swift
//  Add to your test target alongside LocationSimulator.swift.
//
//  Shows the simulator driving a real assertion instead of just being
//  watched on a map: it fast-forwards through the route and checks that
//  the geofence-exit callback actually fires once the simulated position
//  leaves the allowed region.
//
//  Replace `YourApp` below with your actual app module's name.
//

import XCTest
import CoreLocation
@testable import GeoMock_New

final class RegionLockSimulationTests: XCTestCase {

    func testRegionExitFiresWhenRouteLeavesTheGeofence() {
        let route = [
            SimWaypoint(name: "Marina Bay", lat: 1.2836, lng: 103.8607),
            SimWaypoint(name: "Woodlands Checkpoint (SG)", lat: 1.4491, lng: 103.7690),
        ]
        let geofence = SimGeofence(center: route[0].coordinate, radiusMeters: 15_000)

        // Heavily fast-forwarded so the test finishes in ~1s of wall-clock
        // time instead of waiting out a real 30 km/h transit.
        let sim = SimulatedLocationProvider(
            waypoints: route,
            speedKmh: 30,
            rateMultiplier: 2000,
            loop: false,
            geofence: geofence
        )

        let exited = expectation(description: "region exit fires once the route leaves the geofence")
        var sawInsideFirst = false

        sim.onRegionChange = { inside in
            if inside {
                sawInsideFirst = true
            } else {
                exited.fulfill()
            }
        }

        sim.start()
        wait(for: [exited], timeout: 5.0)
        sim.stop()

        XCTAssertTrue(sawInsideFirst, "expected the route to start inside the geofence before exiting")
    }

    func testSimulatedLocationNeverJumpsMoreThanExpectedPerTick() {
        // Guards the "gradual, not teleporting" property itself: consecutive
        // readings should never be farther apart than speed * tick interval
        // (with slack for the 0.2s timer's own scheduling jitter).
        let route = [
            SimWaypoint(name: "A", lat: 1.30, lng: 103.80),
            SimWaypoint(name: "B", lat: 1.35, lng: 103.85),
        ]
        let sim = SimulatedLocationProvider(waypoints: route, speedKmh: 30, rateMultiplier: 50, loop: false)

        var lastLocation: CLLocation?
        var maxJumpMeters: Double = 0
        let gotSeveralUpdates = expectation(description: "collected enough updates to check jump size")
        var updateCount = 0

        sim.onLocationUpdate = { location in
            if let last = lastLocation {
                maxJumpMeters = max(maxJumpMeters, location.distance(from: last))
            }
            lastLocation = location
            updateCount += 1
            if updateCount >= 10 {
                gotSeveralUpdates.fulfill()
            }
        }

        sim.start()
        wait(for: [gotSeveralUpdates], timeout: 5.0)
        sim.stop()

        // speed(30 km/h ≈ 8.33 m/s) * rate(50) * tick(0.2s) ≈ 83m per tick, generously bounded here
        XCTAssertLessThan(maxJumpMeters, 300, "a single tick moved further than the configured speed allows — that would mean it's teleporting, not interpolating")
    }
}
