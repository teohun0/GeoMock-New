# GeoMock

An iOS toolkit for testing region-locking / geofencing logic against **gradual, realistic simulated movement** — never a location that just teleports from point to point.

Built around one core idea: there are two genuinely different ways to mock location on iOS, and they solve different problems.

| | In-app simulation | System-wide via Xcode |
|---|---|---|
| Needs a computer connected? | No | Yes, tethered the whole time |
| Affects your own app's code? | Yes | Yes |
| Affects other apps (Google Maps, etc.)? | No — never, by design | Yes, if a location subscription is held open |
| Works after a normal install? | Yes | No |

Neither of these is a workaround or a trick — they're the two mechanisms Apple actually provides. Nothing installable from the App Store can override another app's live GPS on a real, non-jailbroken device; that's a deliberate sandboxing boundary, not a gap in this project.

## Features

- **Gradual movement** — position is interpolated smoothly between waypoints at a configurable speed, always. No mode in this project ever jumps a route from one point to another instantly.
- **Route library** — save named routes, persisted on-device, select one to start following it immediately.
- **Route Builder** — pin waypoints directly on a map, preview the route live, export it as a GPX file, or import an existing one (including plain GPS-trace exports that use `<trk>`/`<trkseg>` instead of `<wpt>`).
- **Geofence testing** — define a circular region and get live Available/Blocked status plus timestamped enter/exit events, for testing your own region-lock logic against a moving position.
- **GPX tooling for Xcode** — a generator script that writes Xcode-compatible `<wpt>`-based GPX files with real, speed-derived timing (Xcode silently ignores `<trk>`/`<trkseg>` tags and defaults to ~1 point/second without explicit `<time>` deltas).
- **In-app tutorial** — walks through the actual Xcode menu path (Debug ▸ Simulate Location ▸ Add GPX File to Workspace) for anyone using the system-wide route.
- **Bridge toggle** — opens a real `CLLocationManager` subscription so Xcode's Simulate Location has something active to override, which is what allows the simulated position to reach other apps at all.

## Requirements

- Xcode 15+, iOS 17+ deployment target (the map screen uses `Map(position:)`, `MapReader`, and `MapPolyline`, all iOS 17 APIs)
- A free or paid Apple Developer account to run on a physical device (free accounts re-sign every 7 days)

## Project structure

```
Xcode Source Files/        → add to your app target
  WelcomeView.swift           launch screen (Tutorial / Open Google Maps)
  TutorialView.swift          paginated Xcode workflow walkthrough
  GoogleMapsLauncher.swift    opens Google Maps app, falls back to web
  ContentView.swift           route library — select a saved route to follow
  RouteBuilderView.swift      pin/import/export routes on a map
  LocationSimulator.swift     core simulation engine + protocols
  GPXFileSupport.swift        GPX read/write (handles <wpt> and <trkpt>)
  HelpView.swift               in-app instructions

Xcode Test Files/           → add to your test target
  RegionLockSimulationTests.swift

Terminal Tools/              → run from Terminal, never add to Xcode
  generate_gpx.py             build a properly-timed GPX from waypoints
  simulate_route.sh           xcrun simctl wrapper for Simulator automation

Example GPX Files/
  sample routes, various speeds
```

## Setup

1. Add every file under **Xcode Source Files** to your app target (right-click your project folder in the Navigator ▸ Add Files ▸ check the app target only).
2. Add **Xcode Test Files** to your test target instead — XCTest isn't available in a regular app target.
3. In your `@main` App file, set the `WindowGroup`'s root view to `WelcomeView()`.
4. Add two entries under target ▸ **Info** tab ▸ Custom iOS Target Properties:
   - `Privacy - Location When In Use Usage Description` (String) — required for the Bridge toggle to request location permission at all
   - `LSApplicationQueriesSchemes` (Array) → Item 0 (String): `comgooglemaps` — required for the Google Maps button to detect the app correctly instead of always falling back to the web version
5. In `RegionLockSimulationTests.swift`, make sure `@testable import <YourModuleName>` matches your target's actual **Product Module Name** (Build Settings ▸ search "Product Module Name") — this changes if you rename the project, and Xcode converts spaces to underscores.

## Usage

**Follow a saved route (no computer needed):**
Open the app ▸ Tutorial or straight to the route list ▸ tap a route ▸ watch live coordinates update.

**Load a GPX through Xcode (reaches other apps too):**
Add the `.gpx` to the project ▸ run on device/Simulator ▸ Debug ▸ Simulate Location ▸ pick it by name. Use `generate_gpx.py` to build one with correct timing:
```
python3 generate_gpx.py 40 route.gpx waypoints.json
```

**See it reflected in Google Maps or another app:**
Turn on "Bridge to other apps" in the app first, then load the GPX via Xcode as above. Requires staying tethered — disconnecting reverts to real GPS instantly.

## Known gotchas (hit during development, documented so they don't repeat)

- **"Cannot find X in scope"** almost always means a file's Target Membership checkbox isn't set, or it's checked for the wrong target.
- **A `.swift` file added to "Copy Bundle Resources" instead of "Compile Sources"** produces the same "cannot find in scope" error for anything it defines — check target ▸ Build Phases if this happens.
- **Renaming the project** changes the Product Module Name (spaces become underscores) and can leave a stale Info.plist path reference — Product ▸ Clean Build Folder (⇧⌘K) after any rename, before investigating further.
- **`XCTest`/`@testable import` errors** mean the test file is in the wrong target, or the module name in the import doesn't match post-rename.
- Xcode's Simulate Location **only reads `<wpt>` GPX elements** — files exported from fitness/GPS-tracking apps are usually `<trk>`/`<trkseg>` and load silently with no movement. `generate_gpx.py` and the in-app importer both handle this correctly.

## License

No license file included yet — add one (MIT is a reasonable default for a project like this) if you intend for others to reuse or contribute to it.
