//
//  LocationSimulator.swift
//  Drop into your app target (wrap the simulated half in #if DEBUG, or keep
//  it in a test target only — see the usage example at the bottom).
//
//  Gives you a LocationProviding protocol your app's own code should depend
//  on instead of CLLocationManager directly. In production you inject
//  SystemLocationProvider (a thin real wrapper); in tests / debug builds you
//  inject SimulatedLocationProvider, which emits a smooth, gradually
//  interpolated stream of CLLocation updates along a waypoint route —
//  never a teleport — plus geofence enter/exit callbacks so you can assert
//  your region-lock logic actually fires at the right moment.
//
//  This does NOT (and cannot, without a jailbreak) spoof location for any
//  other app on the device — Apple's sandbox doesn't allow that. It moves
//  the location your OWN app receives, which is what you need to unit/UI
//  test region-limiting logic you wrote.
//

import Foundation
import CoreLocation

// MARK: - Waypoint

struct SimWaypoint {
    let name: String
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Geofence (simple circular region, for quick region-lock checks)

struct SimGeofence {
    let center: CLLocationCoordinate2D
    let radiusMeters: Double

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let pointLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return centerLoc.distance(from: pointLoc) <= radiusMeters
    }
}

// MARK: - Protocol your app code should depend on

protocol LocationProviding: AnyObject {
    var onLocationUpdate: ((CLLocation) -> Void)? { get set }
    func start()
    func stop()
}

// MARK: - Real provider — thin wrapper, production code is unaffected

final class SystemLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    var onLocationUpdate: ((CLLocation) -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        onLocationUpdate?(loc)
    }

    // Minimal wrapper — a production app should also handle
    // locationManager(_:didFailWithError:) and authorization status changes.
}

// MARK: - Simulated provider — gradual movement between waypoints, never teleports

final class SimulatedLocationProvider: LocationProviding {
    var onLocationUpdate: ((CLLocation) -> Void)?
    /// Fires only on a transition — true when entering the geofence, false when exiting.
    var onRegionChange: ((Bool) -> Void)?

    private let waypoints: [SimWaypoint]
    private let speedKmh: Double
    private let rateMultiplier: Double
    private let loop: Bool
    private let geofence: SimGeofence?
    private let jitterMeters: Double

    // Precomputed once at init — this is what actually fixes the CPU/heat issue.
    // cumulativeDistances[i] = distance traveled from waypoints[0] to waypoints[i].
    // Without this, tick() was redoing the full haversine pass 2-3x, every 0.2s,
    // for the entire route — trivial for a handful of points, brutal for a
    // 1000+ point imported GPS trace.
    private let cumulativeDistances: [Double]
    private let totalDistance: Double

    private var timer: Timer?
    private var distTraveled: Double = 0
    private var direction: Double = 1
    private var lastFireDate: Date?
    private var wasInside: Bool?

    /// - Parameters:
    ///   - waypoints: route to follow, in order. Needs at least 2 to move.
    ///   - speedKmh: simulated ground speed, reported as-is in CLLocation.speed.
    ///   - rateMultiplier: compresses wall-clock playback time without changing
    ///     the reported speed — e.g. 10x turns a 50-minute route into ~5 minutes
    ///     of test run time. Use 1 for a fully realistic real-time run.
    ///   - loop: when true, bounces back and forth along the route on reaching
    ///     either end (never jumps back to the start).
    ///   - geofence: optional circular region to watch for enter/exit events.
    ///   - jitterMeters: optional random noise added to each reading, to mimic
    ///     real GPS imprecision. 0 disables it.
    init(waypoints: [SimWaypoint],
         speedKmh: Double = 30,
         rateMultiplier: Double = 10,
         loop: Bool = false,
         geofence: SimGeofence? = nil,
         jitterMeters: Double = 0) {
        self.waypoints = waypoints
        self.speedKmh = speedKmh
        self.rateMultiplier = rateMultiplier
        self.loop = loop
        self.geofence = geofence
        self.jitterMeters = jitterMeters

        var cumulative: [Double] = [0]
        if waypoints.count > 1 {
            for i in 0..<(waypoints.count - 1) {
                let segLen = Self.haversine(waypoints[i].coordinate, waypoints[i + 1].coordinate)
                cumulative.append(cumulative[i] + segLen)
            }
        }
        self.cumulativeDistances = cumulative
        self.totalDistance = cumulative.last ?? 0
    }

    func start() {
        guard waypoints.count >= 2 else {
            assertionFailure("SimulatedLocationProvider needs at least 2 waypoints")
            return
        }
        stop()
        distTraveled = 0
        direction = 1
        wasInside = nil
        lastFireDate = Date()

        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick() // emit an immediate first reading at the starting waypoint
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()

        if let last = lastFireDate {
            let dt = now.timeIntervalSince(last)
            let speedMps = speedKmh * 1000 / 3600
            distTraveled += direction * speedMps * dt * rateMultiplier

            if distTraveled >= totalDistance {
                if loop { distTraveled = totalDistance; direction = -1 }
                else { distTraveled = totalDistance; stop() }
            } else if distTraveled <= 0 {
                if loop { distTraveled = 0; direction = 1 }
                else { distTraveled = 0; stop() }
            }
        }
        lastFireDate = now

        var coordinate = position(at: distTraveled)
        if jitterMeters > 0 {
            coordinate = Self.jittered(coordinate, meters: jitterMeters)
        }

        let speedMps = speedKmh * 1000 / 3600
        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: jitterMeters > 0 ? jitterMeters : 5,
            verticalAccuracy: -1,
            course: -1,
            speed: speedMps,
            timestamp: now
        )
        onLocationUpdate?(location)

        if let fence = geofence {
            let inside = fence.contains(coordinate)
            if let was = wasInside, was != inside {
                onRegionChange?(inside)
            }
            wasInside = inside
        }
    }

    // MARK: Math — same approach validated in the browser preview, ported 1:1

    private static func haversine(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Binary search over the precomputed cumulative distances — O(log n),
    /// zero haversine/trig calls. This is what runs on every tick now.
    private func position(at dist: Double) -> CLLocationCoordinate2D {
        guard waypoints.count > 1 else {
            return waypoints.first?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let d = max(0, min(dist, totalDistance))

        var low = 0
        var high = cumulativeDistances.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if cumulativeDistances[mid] <= d {
                low = mid
            } else {
                high = mid
            }
        }
        let segIndex = low
        let segStart = cumulativeDistances[segIndex]
        let segLen = cumulativeDistances[segIndex + 1] - segStart
        let t = segLen == 0 ? 0 : (d - segStart) / segLen

        let a = waypoints[segIndex], b = waypoints[segIndex + 1]
        return CLLocationCoordinate2D(
            latitude: a.lat + (b.lat - a.lat) * t,
            longitude: a.lng + (b.lng - a.lng) * t
        )
    }

    private static func jittered(_ c: CLLocationCoordinate2D, meters: Double) -> CLLocationCoordinate2D {
        let degPerMeter = 1.0 / 111_000.0
        let dLat = (Double.random(in: -1...1)) * meters * degPerMeter
        let dLng = (Double.random(in: -1...1)) * meters * degPerMeter
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLng)
    }
}

// MARK: - Usage example
//
// In production code, depend on the protocol, not CLLocationManager:
//
//   final class RegionLockService {
//       private let locationProvider: LocationProviding
//       init(locationProvider: LocationProviding = SystemLocationProvider()) {
//           self.locationProvider = locationProvider
//           self.locationProvider.onLocationUpdate = { [weak self] location in
//               self?.checkAccess(for: location)
//           }
//       }
//       private func checkAccess(for location: CLLocation) { /* your real logic */ }
//       func start() { locationProvider.start() }
//   }
//
// In a DEBUG build or test target, inject the simulator instead:
//
//   #if DEBUG
//   let route = [
//       SimWaypoint(name: "Marina Bay", lat: 1.2836, lng: 103.8607),
//       SimWaypoint(name: "Woodlands Checkpoint (SG)", lat: 1.4491, lng: 103.7690),
//       SimWaypoint(name: "JB Sultan Iskandar CIQ (MY)", lat: 1.4655, lng: 103.7578),
//       SimWaypoint(name: "Johor Bahru city centre", lat: 1.4927, lng: 103.7414),
//   ]
//   let sim = SimulatedLocationProvider(
//       waypoints: route,
//       speedKmh: 30,
//       rateMultiplier: 10,
//       loop: false,
//       geofence: SimGeofence(center: route[0].coordinate, radiusMeters: 15_000)
//   )
//   sim.onRegionChange = { inside in
//       print(inside ? "ENTER region — unlocked" : "EXIT region — blocked")
//   }
//   let service = RegionLockService(locationProvider: sim)
//   service.start()
//   #endif
