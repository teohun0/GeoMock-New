//
//  GPXFileSupport.swift
//  Writes and reads GPX files using <wpt> elements (the tag Xcode's own
//  Simulate Location actually reads — <trk>/<trkseg> get ignored, so this
//  never writes that form). Shares no code with LocationSimulator.swift
//  on purpose, so either file can be dropped into a project on its own.
//

import Foundation
import CoreLocation

enum GPXFileSupport {

    static func haversine(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6371000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Builds GPX text with real, speed-derived <time> deltas between waypoints,
    /// so Xcode paces playback at an actual speed instead of its ~1pt/sec default.
    static func buildGPX(waypoints: [SimWaypoint], speedKmh: Double) -> String {
        guard !waypoints.isEmpty else { return "" }
        let speedMps = max(speedKmh, 0.1) * 1000 / 3600
        var t = Date(timeIntervalSince1970: 1_704_067_200) // arbitrary start; only deltas matter
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"GeoMock\" xmlns=\"http://www.topografix.com/GPX/1/1\">",
        ]
        for (index, wp) in waypoints.enumerated() {
            if index > 0 {
                let dist = haversine(waypoints[index - 1].coordinate, wp.coordinate)
                t = t.addingTimeInterval(dist / speedMps)
            }
            lines.append("  <wpt lat=\"\(wp.lat)\" lon=\"\(wp.lng)\">")
            lines.append("    <time>\(formatter.string(from: t))</time>")
            lines.append("    <name>\(escapeXML(wp.name))</name>")
            lines.append("  </wpt>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Writes to a temp file so it can be handed straight to a SwiftUI ShareLink.
    static func writeToTempFile(waypoints: [SimWaypoint], speedKmh: Double, filename: String = "geomock-route.gpx") -> URL? {
        let content = buildGPX(waypoints: waypoints, speedKmh: speedKmh)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("GPXFileSupport: failed to write temp file — \(error)")
            return nil
        }
    }
}

/// Reads both <wpt> (what Xcode uses) and <trkpt> (what a lot of other apps
/// export, including things like Tenorshare-style GPS trackers) so importing
/// an existing file works regardless of which one it was built with.
final class GPXParser: NSObject, XMLParserDelegate {
    private var result: [SimWaypoint] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentName = ""
    private var insidePoint = false
    private var textBuffer = ""

    func parse(data: Data) -> [SimWaypoint] {
        result = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "wpt" || elementName == "trkpt" {
            insidePoint = true
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentName = ""
        }
        textBuffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "name" && insidePoint {
            currentName = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if elementName == "wpt" || elementName == "trkpt" {
            if let lat = currentLat, let lon = currentLon {
                let name = currentName.isEmpty ? "Point \(result.count + 1)" : currentName
                result.append(SimWaypoint(name: name, lat: lat, lng: lon))
            }
            insidePoint = false
            currentLat = nil
            currentLon = nil
        }
    }
}

