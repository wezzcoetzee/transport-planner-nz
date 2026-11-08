#if DEBUG
import AppKit
import CoreLocation
import SwiftUI

/// `-uiScreenshots <dir>` renders every screen and state with a fixed Auckland commute to PNGs, then quits.
/// The UI lives in a popover and a status-bar panel, which window capture cannot see, so it is drawn offscreen.
/// `manifest.json` picks which of these become App Store frames; the rest document the other states.
/// `scripts/screenshots.sh` runs this with a pinned afternoon clock and the en_NZ locale, then frames the set.
@MainActor
enum Screenshots {
    static var outputDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiScreenshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }
    static var isEnabled: Bool { outputDirectory != nil }

    private static let office = Place(name: "Commercial Bay, Auckland CBD", latitude: -36.8445, longitude: 174.7672)
    private static let home = Place(name: "Ponsonby Road, Ponsonby", latitude: -36.8570, longitude: 174.7420)

    static func render() async {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        let configured = AppSettings(office: office, home: home)
        func shot(_ name: String, _ view: some View) async { await save(view, to: dir.appendingPathComponent("\(name).png")) }

        model.seedForScreenshots(settings: configured, journeys: demoJourneys(delay: 240), live: true)
        await shot("popover", MenuBarView(model: model))
        let leavingNow = demoJourneys(delay: 240, firstLeaveIn: -4) // the 4 min delay lands the leave time on now
        model.seedForScreenshots(settings: configured, journeys: leavingNow, live: true)
        await shot("leave-now", LeavePrompt(journey: leavingNow[0], model: model))
        await shot("menubar-soon", menuBar(model, journeys: demoJourneys(delay: nil, firstLeaveIn: 8)))
        await shot("menubar-go", menuBar(model, journeys: demoJourneys(delay: nil, firstLeaveIn: 0)))
        await shot("menubar-calm", menuBar(model, journeys: demoJourneys(delay: nil, firstLeaveIn: 25)))

        model.seedForScreenshots(settings: configured, journeys: demoJourneys(delay: nil), live: false)
        await shot("schedule", MenuBarView(model: model))

        // The widest footer: Going (10 minutes out) plus Previous after a skip.
        model.seedForScreenshots(settings: configured, journeys: demoJourneys(delay: nil, firstLeaveIn: 8), live: false, skipped: ["earlier"])
        await shot("skipped", MenuBarView(model: model))

        model.seedForScreenshots(settings: configured, journeys: demoJourneys(delay: nil), live: false,
                                 location: CLLocation(latitude: -36.9, longitude: 174.8))
        await shot("away", MenuBarView(model: model))

        model.seedForScreenshots(settings: AppSettings(), status: "Set up your commute")
        await shot("first-run", MenuBarView(model: model))

        let now = Date.now
        model.seedForScreenshots(settings: configured, status: "Downloading timetable", phase: .downloading(0.42),
                                 fallback: .init(departure: now.addingTimeInterval(14 * 60), arrival: now.addingTimeInterval(38 * 60)))
        await shot("downloading", MenuBarView(model: model))

        model.seedForScreenshots(settings: configured, journeys: demoJourneys(delay: nil), status: "On your way", done: true)
        await shot("done", MenuBarView(model: model))

        var keyed = configured
        keyed.atSubscriptionKey = "demo-key"
        model.seedForScreenshots(settings: keyed, journeys: demoJourneys(delay: 240), live: true, feedVersion: "20261104-1832", stops: demoStops)
        await shot("settings-commute", settingsPage(model, .commute))
        await shot("settings-route", settingsPage(model, .route))
        await shot("settings-data", settingsPage(model, .data))

        model.seedForScreenshots(settings: AppSettings(), status: "Set up your commute")
        await shot("settings-first-run", settingsPage(model, .commute))
        NSApp.terminate(nil)
    }

    /// One Settings tab at its window size without the tab bar, which offscreen drawing cannot render.
    private static func settingsPage(_ model: AppModel, _ tab: SettingsView.Tab) -> some View {
        SettingsView(model: model).page(tab).frame(width: 520).background(.black).preferredColorScheme(.dark)
    }

    /// The status item as it sits in a dark menu bar.
    private static func menuBar(_ model: AppModel, journeys: [Journey]) -> some View {
        model.seedForScreenshots(settings: AppSettings(office: office, home: home), journeys: journeys, live: false)
        return MenuBarLabel(model: model).padding(.horizontal, 10).frame(height: 24).background(.black).preferredColorScheme(.dark)
    }

    /// Drawn at twice the size on a 2x backing store, so the marketing frames stay sharp when the 360 pt
    /// popover fills a 2880 px canvas. ImageRenderer would be simpler but cannot draw AppKit-backed buttons.
    /// Waits a beat after layout so `.task` modifiers (stop lists) have filled in.
    private static func save(_ view: some View, to url: URL) async {
        let zoom: CGFloat = 2
        let size = NSHostingView(rootView: view).fittingSize
        let host = NSHostingView(rootView: view.scaleEffect(zoom, anchor: .topLeading)
            .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading).background(.black))
        host.frame.size = NSSize(width: size.width * zoom, height: size.height * zoom)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func stop(_ id: String, _ code: String, _ name: String) -> Stop {
        Stop(id: id, code: code, name: name, latitude: 0, longitude: 0, parentStation: nil)
    }

    private static func demoStops(_ place: Place) -> [(stop: Stop, distance: Double)] {
        place == office
            ? [(stop("1", "7036", "Lower Albert Street"), 140), (stop("2", "1315", "Customs Street West"), 210),
               (stop("5", "7058", "Britomart Train Station"), 260), (stop("6", "1325", "Queen Street"), 380)]
            : [(stop("3", "8124", "Ponsonby Road"), 120), (stop("7", "8131", "Franklin Road"), 330)]
    }

    /// Four departures from `firstLeaveIn` minutes out; the second needs a transfer.
    private static func demoJourneys(delay: Int?, firstLeaveIn: Double = 12) -> [Journey] {
        let now = Date.now
        func route(_ name: String) -> Route { Route(id: name, shortName: name, longName: name, type: 3, color: nil) }
        let lower = stop("1", "7036", "Lower Albert Street"), customs = stop("2", "1315", "Customs Street West")
        let ponsonby = stop("3", "8124", "Ponsonby Road"), k = stop("4", "7110", "Karangahape Road")
        func ride(_ r: String, _ headsign: String, _ from: Stop, _ to: Stop, _ dep: Double, _ mins: Double, _ stops: Int) -> Leg {
            let d = now.addingTimeInterval(dep * 60)
            return Leg(kind: .ride(route: route(r), trip: TripInfo(id: "\(r)-\(dep)", routeID: r, headsign: headsign), board: from, alight: to, boardSequence: 1, stops: stops),
                       departure: d, arrival: d.addingTimeInterval(mins * 60))
        }
        func walk(_ m: Double, _ start: Double, _ mins: Double) -> Leg {
            Leg(kind: .walk(meters: m), departure: now.addingTimeInterval(start * 60), arrival: now.addingTimeInterval((start + mins) * 60))
        }
        func direct(_ r: String, _ headsign: String, _ leave: Double, _ ride_: Double, _ stops: Int) -> Journey {
            Journey(legs: [walk(320, leave, 5), ride(r, headsign, lower, ponsonby, leave + 6.5, ride_, stops), walk(240, leave + 6.5 + ride_, 3)])
        }
        let t = firstLeaveIn
        var first = direct("INN", "Inner Link Anticlockwise", t, 14, 9)
        if let delay { _ = first.applyDelay(delay) }
        let transfer = Journey(legs: [walk(180, t + 7, 3), ride("OUT", "Outer Link", customs, k, t + 11.5, 8, 5), walk(0, t + 19.5, 0),
                                      ride("NX2", "Westgate", k, ponsonby, t + 22, 6, 3), walk(240, t + 28, 3)])
        return [first, transfer, direct("INN", "Inner Link Anticlockwise", t + 15, 15, 9), direct("INN", "Inner Link Anticlockwise", t + 30, 14, 9)]
    }
}
#endif
