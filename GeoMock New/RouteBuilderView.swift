//
//  RouteBuilderView.swift
//  Pin waypoints directly on a map, then either drive them straight into
//  SimulatedLocationProvider for an immediate live test, or export them as
//  a real GPX file to use with Xcode's Debug > Simulate Location instead.
//
//  Requires iOS 17+ (Map(position:), MapReader, MapPolyline, Annotation are
//  all iOS 17 APIs — check your target's Minimum Deployments if this won't build).
//
//  Uses SpatialTapGesture instead of .onTapGesture for the map tap handler:
//  .onTapGesture on Map broke on iOS 26 (a known Apple bug); the
//  .simultaneousGesture(SpatialTapGesture()...) form below is the documented
//  workaround and also works fine on older iOS versions.
//

import SwiftUI
import MapKit
import CoreLocation
import UniformTypeIdentifiers

struct RouteBuilderView: View {
    var onSave: ((String, [SimWaypoint], Double) -> Void)? = nil

    @State private var waypoints: [SimWaypoint] = []
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
    )

    @State private var currentPosition: CLLocationCoordinate2D?
    @State private var currentSpeed: Double = 0
    @State private var sourceLabel: String = "No route loaded yet"
    @State private var isSimulating = false
    @State private var speedKmh: Double = 40

    @State private var activeSimulator: SimulatedLocationProvider?
    @State private var exportURL: URL?
    @State private var showFileImporter = false
    @State private var showImportError = false
    @State private var importErrorMessage: String = ""
    @State private var showSaveDialog = false
    @State private var routeName: String = ""

    private struct MarkerInfo {
        let point: SimWaypoint
        let label: String
    }

    /// Full detail (numbered pins) for a hand-pinned route; for a dense
    /// imported trace (hundreds/thousands of points), only Start/End get a
    /// Marker — MapKit laying out one annotation view per point is what was
    /// actually burning the CPU, not the polyline itself.
    private var markerWaypoints: [MarkerInfo] {
        let threshold = 50
        if waypoints.count <= threshold {
            return waypoints.enumerated().map { index, wp in
                MarkerInfo(point: wp, label: "\(index + 1)")
            }
        } else {
            var result: [MarkerInfo] = []
            if let first = waypoints.first {
                result.append(MarkerInfo(point: first, label: "Start"))
            }
            if let last = waypoints.last {
                result.append(MarkerInfo(point: last, label: "End"))
            }
            return result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if waypoints.count >= 2 {
                        MapPolyline(coordinates: waypoints.map(\.coordinate))
                            .stroke(.blue, lineWidth: 3)
                    }
                    ForEach(Array(markerWaypoints.enumerated()), id: \.offset) { index, wp in
                        Marker(wp.label, coordinate: wp.point.coordinate)
                            .tint(.purple)
                    }
                    if let current = currentPosition {
                        Annotation("Mocked position", coordinate: current) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(radius: 3)
                        }
                    }
                }
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        if let coordinate = proxy.convert(value.location, from: .local) {
                            waypoints.append(SimWaypoint(
                                name: "Point \(waypoints.count + 1)",
                                lat: coordinate.latitude,
                                lng: coordinate.longitude
                            ))
                            exportURL = nil
                        }
                    }
                )
            }
            .frame(height: 320)

            statusBar

            if waypoints.count > 50 {
                HStack {
                    Text("\(waypoints.count) points loaded (too many to list individually)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            } else {
                List {
                    ForEach(Array(waypoints.enumerated()), id: \.offset) { index, wp in
                        HStack {
                            Text("\(index + 1). \(wp.name)")
                            Spacer()
                            Text(String(format: "%.4f, %.4f", wp.lat, wp.lng))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                waypoints.remove(at: index)
                                exportURL = nil
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }

            controls
        }
        .navigationTitle("Route Builder")
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
        .alert("Couldn't read that file", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
        .alert("Name this route", isPresented: $showSaveDialog) {
            TextField("Route name", text: $routeName)
            Button("Save") {
                let name = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave?(name.isEmpty ? "Untitled route" : name, waypoints, speedKmh)
                routeName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
            HStack {
                if let pos = currentPosition {
                    Text(String(format: "%.5f, %.5f", pos.latitude, pos.longitude))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(String(format: "%.1f m/s", currentSpeed))
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("Not simulating").font(.system(.body, design: .monospaced))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Speed: \(Int(speedKmh)) km/h")
                Slider(value: $speedKmh, in: 1...150, step: 1)
            }

            HStack {
                Button(isSimulating ? "Stop" : "Start Simulating") {
                    isSimulating ? stopSimulating() : startSimulating()
                }
                .disabled(!isSimulating && waypoints.count < 2)
                .buttonStyle(.borderedProminent)

                Button("Import GPX") {
                    showFileImporter = true
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    stopSimulating()
                    waypoints = []
                    currentPosition = nil
                    exportURL = nil
                    sourceLabel = "No route loaded yet"
                }
                .buttonStyle(.bordered)
            }

            if onSave != nil {
                Button("Save to Library") {
                    showSaveDialog = true
                }
                .disabled(waypoints.count < 2)
                .buttonStyle(.bordered)
            }

            if let url = exportURL {
                ShareLink(item: url) {
                    Label("Share GPX (\(waypoints.count) points)", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            } else {
                Button("Generate GPX to share") {
                    exportURL = GPXFileSupport.writeToTempFile(waypoints: waypoints, speedKmh: speedKmh)
                }
                .disabled(waypoints.isEmpty)
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private func startSimulating() {
        guard waypoints.count >= 2 else { return }
        let sim = SimulatedLocationProvider(waypoints: waypoints, speedKmh: speedKmh, rateMultiplier: 10, loop: false)
        sim.onLocationUpdate = { location in
            currentPosition = location.coordinate
            currentSpeed = location.speed
        }
        sim.start()
        activeSimulator = sim
        isSimulating = true
        sourceLabel = "Simulating: pinned route (\(waypoints.count) points, \(Int(speedKmh)) km/h)"
    }

    private func stopSimulating() {
        activeSimulator?.stop()
        activeSimulator = nil
        isSimulating = false
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importErrorMessage = "Couldn't get permission to read that file."
                showImportError = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                importErrorMessage = "Couldn't open that file."
                showImportError = true
                return
            }
            let parsed = GPXParser().parse(data: data)
            if parsed.isEmpty {
                importErrorMessage = "No <wpt> or <trkpt> points found in that GPX."
                showImportError = true
                return
            }
            stopSimulating()
            waypoints = parsed
            exportURL = nil
            currentPosition = nil
            sourceLabel = "Loaded: \(url.lastPathComponent) (\(parsed.count) points)"
            if let first = parsed.first {
                cameraPosition = .region(
                    MKCoordinateRegion(center: first.coordinate,
                                       span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))
                )
            }
        }
    }
}

#Preview {
    NavigationStack {
        RouteBuilderView()
    }
}
