import SwiftUI
import CoreLocation
import Combine

// MARK: - Manual Codable conformance (must be manual, not synthesized, since this
// extension lives in a different file than SimWaypoint's declaration)
extension SimWaypoint: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, lat, lng
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let lat = try container.decode(Double.self, forKey: .lat)
        let lng = try container.decode(Double.self, forKey: .lng)
        self.init(name: name, lat: lat, lng: lng)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
    }
}

// MARK: - A named, saveable route

struct SavedRoute: Identifiable, Codable {
    let id: UUID
    var name: String
    var waypoints: [SimWaypoint]
    var speedKmh: Double

    init(id: UUID = UUID(), name: String, waypoints: [SimWaypoint], speedKmh: Double) {
        self.id = id
        self.name = name
        self.waypoints = waypoints
        self.speedKmh = speedKmh
    }

    static let demoRoute = SavedRoute(
        name: "Marina Bay → Johor Bahru (demo)",
        waypoints: [
            SimWaypoint(name: "Marina Bay", lat: 1.2836, lng: 103.8607),
            SimWaypoint(name: "Woodlands Checkpoint (SG)", lat: 1.4491, lng: 103.7690),
            SimWaypoint(name: "JB Sultan Iskandar CIQ (MY)", lat: 1.4655, lng: 103.7578),
            SimWaypoint(name: "Johor Bahru city centre", lat: 1.4927, lng: 103.7414),
        ],
        speedKmh: 30
    )
}

// MARK: - Persists to UserDefaults so routes survive app relaunch, no server/computer involved

final class RouteLibraryStore: ObservableObject {
    @Published var routes: [SavedRoute] = []
    private let key = "geomock.savedRoutes"

    init() {
        load()
        if routes.isEmpty {
            routes = [SavedRoute.demoRoute]
            save()
        }
    }

    func add(_ route: SavedRoute) {
        routes.append(route)
        save()
    }

    func delete(at offsets: IndexSet) {
        routes.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(routes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedRoute].self, from: data) else { return }
        routes = decoded
    }
}

// MARK: - Main screen: pick a route, it starts following immediately, no Xcode/cable needed

struct ContentView: View {
    @StateObject private var store = RouteLibraryStore()
    @State private var activeRoute: SavedRoute?
    @State private var activeSimulator: SimulatedLocationProvider?
    @State private var currentPosition: CLLocationCoordinate2D?
    @State private var currentSpeed: Double = 0

    // Holds a REAL CLLocationManager subscription open — not to read its data,
    // just so Xcode's Debug > Simulate Location (system-wide, GPX-based) has
    // something active to override. Without this, other apps like Google Maps
    // never see the simulated location, no matter what's loaded in Xcode.
    @State private var systemBridge: SystemLocationProvider?
    @State private var bridgeActive = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                bridgeCard

                if let route = activeRoute {
                    activeStatusCard(route)
                }

                List {
                    ForEach(store.routes) { route in
                        Button {
                            select(route)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.name)
                                    Text("\(route.waypoints.count) points · \(Int(route.speedKmh)) km/h")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if activeRoute?.id == route.id {
                                    Image(systemName: "location.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        for index in offsets where store.routes[index].id == activeRoute?.id {
                            stop()
                        }
                        store.delete(at: offsets)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("New Route") {
                        RouteBuilderView(onSave: { name, waypoints, speed in
                            store.add(SavedRoute(name: name, waypoints: waypoints, speedKmh: speed))
                        })
                    }
                }
            }
        }
    }

    private func select(_ route: SavedRoute) {
        guard route.waypoints.count >= 2 else { return }
        activeSimulator?.stop()
        let sim = SimulatedLocationProvider(waypoints: route.waypoints, speedKmh: route.speedKmh, rateMultiplier: 10, loop: false)
        sim.onLocationUpdate = { location in
            currentPosition = location.coordinate
            currentSpeed = location.speed
        }
        sim.start()
        activeSimulator = sim
        activeRoute = route
    }

    private func stop() {
        activeSimulator?.stop()
        activeSimulator = nil
        activeRoute = nil
        currentPosition = nil
    }

    private var bridgeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Bridge to other apps (needs Xcode + GPX)", isOn: Binding(
                get: { bridgeActive },
                set: { newValue in
                    newValue ? startBridge() : stopBridge()
                }
            ))
            .font(.subheadline)
            Text("Turns on real location services, purely so Xcode's Debug ▸ Simulate Location has an active subscription to override. Only matters if you're tethered to a Mac with a GPX loaded — does nothing on its own.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
    }

    private func startBridge() {
        let bridge = SystemLocationProvider()
        bridge.start()
        systemBridge = bridge
        bridgeActive = true
    }

    private func stopBridge() {
        systemBridge?.stop()
        systemBridge = nil
        bridgeActive = false
    }

    private func activeStatusCard(_ route: SavedRoute) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Following: \(route.name)").font(.headline)
                Spacer()
                Button("Stop", action: stop)
            }
            if let pos = currentPosition {
                Text(String(format: "%.5f, %.5f — %.1f m/s", pos.latitude, pos.longitude, currentSpeed))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

#Preview {
    ContentView()
}
