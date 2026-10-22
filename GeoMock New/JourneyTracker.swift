//
//  JourneyTracker.swift
//  Works out how far along a route you are, live.
//
//  It reads the phone's current location (the real GPS, or the simulated
//  position while Xcode's Debug > Simulate Location is playing a GPX file),
//  compares it with the two GPX routes bundled inside the app (650385 and
//  Draycott, the same ones the Timer tab is named after) and reports:
//  distance covered and left, how far off the route you are, measured speed,
//  and an arrival estimate.
//
//  Two things about these routes shape the matching:
//    • Both are closed loops (they finish where they start), and they run along
//      the same roads for long stretches, partly with each other and partly with
//      themselves. So "nearest point on the route" alone is ambiguous. The tracker
//      remembers where it last was on each route and prefers the stretch you'd
//      reach by carrying on at your current speed.
//    • If it starts out on the wrong pass of a repeated road, it corrects itself as
//      soon as the two passes split apart (usually within a minute of driving).
//
//  Tracking runs while GeoMock is open. iOS doesn't deliver location to an app
//  that has no background-location permission once it is suspended, so when you
//  come back from Google Maps the tracker just catches up from the latest fix.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Route geometry

/// One route as a polyline, flattened to metres around its own centre so the
/// distance maths is plain geometry. Accurate to well under 0.1% at this scale.
struct RoutePath {
    let id: String
    let title: String

    private let lat0: Double
    private let lon0: Double
    private let cosLat0: Double
    private let xs: [Double]
    private let ys: [Double]
    /// Metres travelled along the route at each vertex (0 at the start).
    private let cum: [Double]

    /// Where the position sits on the route.
    struct Fix {
        /// Metres from the start, measured along the route.
        let along: Double
        /// Metres between the position and the route line.
        let offRoute: Double
    }

    private static let earthRadius = 6_371_008.8
    /// Two stretches of road count as "the same place" when they're this close (metres).
    private static let passTolerance = 15.0

    var length: Double { cum.last ?? 0 }

    init?(id: String, title: String, points: [(lat: Double, lon: Double)]) {
        guard points.count >= 2 else { return nil }
        let metresPerDegree = RoutePath.earthRadius * Double.pi / 180
        let meanLat = points.reduce(0) { $0 + $1.lat } / Double(points.count)
        let meanLon = points.reduce(0) { $0 + $1.lon } / Double(points.count)
        let cosLat = cos(meanLat * Double.pi / 180)

        var xs: [Double] = []
        var ys: [Double] = []
        var cum: [Double] = []
        for p in points {
            let x = (p.lon - meanLon) * metresPerDegree * cosLat
            let y = (p.lat - meanLat) * metresPerDegree
            if let lastX = xs.last, let lastY = ys.last, let lastCum = cum.last {
                let step = hypot(x - lastX, y - lastY)
                if step < 0.5 { continue }          // the hold at the end repeats one coordinate
                cum.append(lastCum + step)
            } else {
                cum.append(0)
            }
            xs.append(x)
            ys.append(y)
        }
        guard xs.count >= 2, let total = cum.last, total > 100 else { return nil }

        self.id = id
        self.title = title
        self.lat0 = meanLat
        self.lon0 = meanLon
        self.cosLat0 = cosLat
        self.xs = xs
        self.ys = ys
        self.cum = cum
    }

    private func flatten(lat: Double, lon: Double) -> (x: Double, y: Double) {
        let metresPerDegree = RoutePath.earthRadius * Double.pi / 180
        return ((lon - lon0) * metresPerDegree * cosLat0, (lat - lat0) * metresPerDegree)
    }

    /// Index of the segment that contains this distance along the route.
    private func segment(containing along: Double) -> Int {
        var lo = 0
        var hi = cum.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cum[mid] <= along { lo = mid } else { hi = mid - 1 }
        }
        return min(max(lo, 0), cum.count - 2)
    }

    /// Metres between a position and the final point of the route.
    func metresFromEnd(lat: Double, lon: Double) -> Double {
        let p = flatten(lat: lat, lon: lon)
        return hypot(p.x - (xs.last ?? 0), p.y - (ys.last ?? 0))
    }

    /// The closest point on the route to a position.
    /// - alongRange: only look at this stretch of the route (nil = the whole route).
    /// - expectedAlong: when the route passes the same spot more than once, prefer the pass
    ///   nearest this distance. With nil, the earliest pass wins.
    func nearest(lat: Double,
                 lon: Double,
                 alongRange: ClosedRange<Double>? = nil,
                 expectedAlong: Double? = nil) -> Fix? {
        let p = flatten(lat: lat, lon: lon)

        let first: Int
        let last: Int
        if let range = alongRange {
            first = segment(containing: range.lowerBound)
            last = segment(containing: range.upperBound)
        } else {
            first = 0
            last = xs.count - 2
        }
        guard first <= last else { return nil }

        var alongs: [Double] = []
        var dists: [Double] = []
        alongs.reserveCapacity(last - first + 1)
        dists.reserveCapacity(last - first + 1)
        var best = Double.infinity

        for i in first...last {
            let ax = xs[i]
            let ay = ys[i]
            let dx = xs[i + 1] - ax
            let dy = ys[i + 1] - ay
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? ((p.x - ax) * dx + (p.y - ay) * dy) / len2 : 0
            t = min(max(t, 0), 1)
            let d = hypot(p.x - (ax + t * dx), p.y - (ay + t * dy))
            alongs.append(cum[i] + t * (cum[i + 1] - cum[i]))
            dists.append(d)
            if d < best { best = d }
        }

        // Every stretch about as close as the closest one is a candidate "pass" of this spot.
        let limit = best + RoutePath.passTolerance
        var chosen: Int?
        for k in 0..<dists.count where dists[k] <= limit {
            guard let expected = expectedAlong else { chosen = k; break }
            if let c = chosen {
                if abs(alongs[k] - expected) < abs(alongs[c] - expected) { chosen = k }
            } else {
                chosen = k
            }
        }
        guard let k = chosen else { return nil }
        return Fix(along: alongs[k], offRoute: dists[k])
    }
}

// MARK: - GPX reading

/// Pulls the coordinates out of a GPX file. Handles Xcode-style <wpt> points and
/// ordinary <trkpt> track points. Not tied to the main actor so it can be used from anywhere.
nonisolated private final class GPXPointParser: NSObject, XMLParserDelegate {
    private(set) var points: [(lat: Double, lon: Double)] = []

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName == "wpt" || elementName == "trkpt",
              let lat = attributeDict["lat"].flatMap({ Double($0) }),
              let lon = attributeDict["lon"].flatMap({ Double($0) }) else { return }
        points.append((lat, lon))
    }
}

// MARK: - Location delivery

/// CoreLocation's delegate, kept apart from the (main-actor) tracker the same way
/// NotificationRouter is: it just hands whatever arrives to the tracker.
nonisolated final class JourneyLocationBridge: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    var onLocations: (@Sendable ([CLLocation]) -> Void)?
    var onAuthorizationChange: (@Sendable () -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onLocations?(locations)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // "Can't get a fix right now" is routine (indoors, just launched); CoreLocation keeps trying.
    }
}

// MARK: - Tracker

final class JourneyTracker: ObservableObject {

    /// Which route to measure against.
    enum Mode: Hashable {
        /// Pick whichever route the position is on.
        case auto
        /// Lock to one route (a TimerRoute id).
        case route(String)
    }

    /// Everything the Progress tab shows, worked out from one location fix.
    struct Snapshot: Equatable {
        enum State {
            case atStart, onRoute, offRoute, finished, notNearRoute
        }

        let routeID: String
        let routeTitle: String
        let state: State
        let alongMeters: Double
        let lengthMeters: Double
        let offRouteMeters: Double
        let speedKmh: Double?
        let etaDate: Date?
        let fixDate: Date
        /// The other route's name while the position fits both and it can't tell which one you're on.
        let alsoMatches: String?

        var fraction: Double { lengthMeters > 0 ? min(max(alongMeters / lengthMeters, 0), 1) : 0 }
        var remainingMeters: Double { max(lengthMeters - alongMeters, 0) }
    }

    @Published var mode: Mode = .auto {
        didSet { if mode != oldValue { modeChanged() } }
    }
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var isTracking = false
    /// Set when a route's GPX file isn't inside the app. nil = all good.
    @Published private(set) var routeFilesProblem: String?

    var hasRoutes: Bool { !routes.isEmpty }
    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    // Position is "on the route" within this many metres; beyond it you're off route;
    // beyond the second figure the tracker says you're not near a route at all.
    private static let onRouteLimit = 100.0
    private static let nearRouteLimit = 1500.0

    private let manager: CLLocationManager
    private let bridge = JourneyLocationBridge()

    private var routes: [RoutePath] = []
    private var routesLoaded = false
    private var wantsTracking = false
    private var hasAutoStarted = false

    private var lastLocation: CLLocation?
    private var recent: [CLLocation] = []
    /// Per route: the last place it put you (metres along) and when.
    private var memory: [String: (along: Double, date: Date)] = [:]
    private var chosenRouteID: String?
    private var choiceIsAmbiguous = false

    init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorization = manager.authorizationStatus

        manager.delegate = bridge
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false

        bridge.onLocations = { [weak self] locations in
            guard let latest = locations.last else { return }
            Task { @MainActor [weak self] in self?.handle(latest) }
        }
        bridge.onAuthorizationChange = { [weak self] in
            Task { @MainActor [weak self] in self?.authorizationDidChange() }
        }    }

    // MARK: Controls

    /// The Progress tab calls this when it first appears, so the location prompt waits
    /// until you actually open the tab. Later visits don't undo a pause.
    func startOnce() {
        guard !hasAutoStarted else { return }
        hasAutoStarted = true
        start()
    }

    func start() {
        wantsTracking = true
        loadRoutesIfNeeded()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            isTracking = true
        default:
            break
        }
    }

    func stop() {
        wantsTracking = false
        manager.stopUpdatingLocation()
        isTracking = false
    }

    /// Call when the app returns to the foreground.
    func resumeIfNeeded() {
        if wantsTracking { start() }
    }

    /// Forgets where it thought you were, so the next fix starts from scratch
    /// (use after replaying a route).
    func resetProgress() {
        memory.removeAll()
        chosenRouteID = nil
        choiceIsAmbiguous = false
        snapshot = nil
        if let location = lastLocation { update(from: location) }
    }

    private func modeChanged() {
        chosenRouteID = nil
        choiceIsAmbiguous = false
        if let location = lastLocation { update(from: location) }
    }

    private func authorizationDidChange() {
        authorization = manager.authorizationStatus
        if wantsTracking && isAuthorized {
            manager.startUpdatingLocation()
            isTracking = true
        } else if !isAuthorized {
            isTracking = false
        }
    }

    // MARK: Loading the routes

    private func loadRoutesIfNeeded() {
        guard !routesLoaded else { return }
        routesLoaded = true

        let urls = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) ?? []
        var loaded: [RoutePath] = []
        for spec in TimerRoute.all {
            guard let url = Self.bestFile(in: urls, forRouteNamed: spec.title),
                  let data = try? Data(contentsOf: url) else { continue }
            let reader = GPXPointParser()
            let xml = XMLParser(data: data)
            xml.delegate = reader
            guard xml.parse(),
                  let route = RoutePath(id: spec.id, title: spec.title, points: reader.points) else { continue }
            loaded.append(route)
        }
        routes = loaded

        let missing = TimerRoute.all.filter { spec in !loaded.contains { $0.id == spec.id } }.map(\.title)
        if !missing.isEmpty {
            routeFilesProblem = "Couldn't find the GPX file for \(missing.joined(separator: " and ")) inside the app. In Xcode, select the .gpx file, open the File Inspector (⌥⌘1) and tick “GeoMock New” under Target Membership."
        }
    }

    /// The bundled GPX whose file name starts with the route's name. If there are several,
    /// the 100 km/h one wins, then the highest version number.
    private static func bestFile(in urls: [URL], forRouteNamed name: String) -> URL? {
        let prefix = name.lowercased()
        let matches = urls.filter { $0.lastPathComponent.lowercased().hasPrefix(prefix) }
        return matches.max { a, b in
            let aName = a.lastPathComponent
            let bName = b.lastPathComponent
            let aFast = aName.lowercased().contains("100kmh")
            let bFast = bName.lowercased().contains("100kmh")
            if aFast != bFast { return !aFast && bFast }
            return aName.localizedStandardCompare(bName) == .orderedAscending
        }
    }

    // MARK: Handling a fix

    private func handle(_ location: CLLocation) {
        // A negative accuracy means iOS couldn't actually place the phone.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500 else { return }
        lastLocation = location

        recent.append(location)
        recent.removeAll { location.timestamp.timeIntervalSince($0.timestamp) > 12 }

        update(from: location)
    }

    /// Speed over roughly the last 12 seconds, from the straight-line distance between the
    /// oldest and newest fix (steady even when the phone is stationary and the fix jitters).
    private var measuredSpeed: Double? {
        guard recent.count >= 3, let first = recent.first, let last = recent.last else { return nil }
        let seconds = last.timestamp.timeIntervalSince(first.timestamp)
        guard seconds >= 3 else { return nil }
        let metres = last.distance(from: first)
        return metres < 3 ? 0 : metres / seconds
    }

    private func update(from location: CLLocation) {
        guard !routes.isEmpty else { return }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let speed = measuredSpeed

        let pool: [RoutePath]
        switch mode {
        case .auto:
            pool = routes
        case .route(let id):
            pool = routes.filter { $0.id == id }
        }

        var fixes: [(route: RoutePath, fix: RoutePath.Fix)] = []
        for route in pool {
            if let fix = locate(on: route, lat: lat, lon: lon, at: location.timestamp, speed: speed ?? 0) {
                fixes.append((route, fix))
            }
        }
        guard var best = fixes.min(by: { $0.fix.offRoute < $1.fix.offRoute }) else { return }

        // Stay on the route we were already following unless the other is clearly the better match.
        if let previousID = chosenRouteID,
           let previous = fixes.first(where: { $0.route.id == previousID }),
           previous.fix.offRoute <= best.fix.offRoute + 40 {
            best = previous
        }

        let others = fixes.filter { $0.route.id != best.route.id }
        if best.route.id != chosenRouteID {
            chosenRouteID = best.route.id
            choiceIsAmbiguous = others.contains { $0.fix.offRoute <= 40 }
        } else if choiceIsAmbiguous,
                  best.fix.offRoute <= 50,
                  others.allSatisfy({ $0.fix.offRoute > 150 }) {
            choiceIsAmbiguous = false           // the routes have drawn apart; this one is clearly it
        }
        let alsoMatches = choiceIsAmbiguous
            ? others.first(where: { $0.fix.offRoute <= 40 })?.route.title
            : nil

        let route = best.route
        let fix = best.fix
        let state: Snapshot.State
        if fix.offRoute > Self.nearRouteLimit {
            state = .notNearRoute
        } else if fix.offRoute > Self.onRouteLimit {
            state = .offRoute
        } else if fix.along >= route.length - 100 {
            state = .finished
        } else if fix.along < 100 {
            state = .atStart
        } else {
            state = .onRoute
        }

        var eta: Date?
        if let v = speed, v >= 1.5, [.atStart, .onRoute, .offRoute].contains(state) {
            let seconds = (route.length - fix.along) / v
            if seconds < 6 * 3600 { eta = Date().addingTimeInterval(seconds) }
        }

        snapshot = Snapshot(routeID: route.id,
                            routeTitle: route.title,
                            state: state,
                            alongMeters: fix.along,
                            lengthMeters: route.length,
                            offRouteMeters: fix.offRoute,
                            speedKmh: speed.map { $0 * 3.6 },
                            etaDate: eta,
                            fixDate: location.timestamp,
                            alsoMatches: alsoMatches)
    }

    /// Finds where on one route the position is, using what it remembers of the last fix.
    private func locate(on route: RoutePath,
                        lat: Double,
                        lon: Double,
                        at date: Date,
                        speed: Double) -> RoutePath.Fix? {
        var remembered = memory[route.id]

        // Finished last time: stay "finished" while parked at the end, but once the phone
        // moves away from the finish point it's a new run starting from the beginning.
        if let m = remembered, m.along >= route.length - 150,
           route.metresFromEnd(lat: lat, lon: lon) > 60 {
            remembered = nil
        }

        var fix: RoutePath.Fix?
        if let m = remembered {
            let elapsed = max(date.timeIntervalSince(m.date), 0)
            // Room to have moved since the last fix, which can be long ago if the app was in the background.
            let reach = max(3000, elapsed * 45)
            let expected = m.along + elapsed * speed
            fix = route.nearest(lat: lat,
                                lon: lon,
                                alongRange: (m.along - 300)...(m.along + reach),
                                expectedAlong: expected)
            // Nothing close in that stretch: the phone may have jumped (or the route restarted). Look everywhere.
            if (fix?.offRoute ?? .infinity) > 250,
               let anywhere = route.nearest(lat: lat, lon: lon),
               anywhere.offRoute < (fix?.offRoute ?? .infinity) - 50 {
                fix = anywhere
            }
        } else {
            fix = route.nearest(lat: lat, lon: lon)
        }

        if let fix { memory[route.id] = (fix.along, date) }
        return fix
    }
}
