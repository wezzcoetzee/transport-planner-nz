#if DEBUG
import AppKit
import SwiftUI

/// `-uiScreenshots <dir>` renders the popover and leave panel with a fixed Auckland commute to PNGs, then quits.
/// The UI lives in a popover and a status-bar panel, which window capture cannot see, so it is drawn offscreen.
@MainActor
enum Screenshots {
    static var outputDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiScreenshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }
    static var isEnabled: Bool { outputDirectory != nil }

    static func render() {
        guard let dir = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel.shared
        let settings = AppSettings(office: Place(name: "Commercial Bay", latitude: -36.8445, longitude: 174.7672),
                                   home: Place(name: "Ponsonby", latitude: -36.8570, longitude: 174.7420))

        model.seedForScreenshots(settings: settings, journeys: demoJourneys(delay: 120), live: true)
        save(MenuBarView(model: model), to: dir.appendingPathComponent("popover.png"))
        save(LeavePrompt(journey: demoJourneys(delay: 120)[0], model: model), to: dir.appendingPathComponent("leave-now.png"))
        model.seedForScreenshots(settings: settings, journeys: demoJourneys(delay: nil), live: false)
        save(MenuBarView(model: model), to: dir.appendingPathComponent("schedule.png"))
        NSApp.terminate(nil)
    }

    /// Drawn at twice the size on a 2x backing store, so the marketing frames stay sharp when the 360 pt
    /// popover fills a 2880 px canvas. ImageRenderer would be simpler but cannot draw AppKit-backed buttons.
    private static func save(_ view: some View, to url: URL) {
        let zoom: CGFloat = 2
        let size = NSHostingView(rootView: view).fittingSize
        let host = NSHostingView(rootView: view.scaleEffect(zoom).frame(width: size.width * zoom, height: size.height * zoom))
        host.frame.size = NSSize(width: size.width * zoom, height: size.height * zoom)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Four departures from 12 minutes out; the second needs a transfer.
    private static func demoJourneys(delay: Int?) -> [Journey] {
        let now = Date.now
        func stop(_ id: String, _ name: String) -> Stop { Stop(id: id, code: id, name: name, latitude: 0, longitude: 0, parentStation: nil) }
        func route(_ name: String) -> Route { Route(id: name, shortName: name, longName: name, type: 3, color: nil) }
        let lower = stop("1", "Lower Albert Street"), customs = stop("2", "Customs Street West")
        let ponsonby = stop("3", "Ponsonby Road"), k = stop("4", "Karangahape Road")
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
        var first = direct("INN", "Inner Link Anticlockwise", 12, 14, 9)
        if let delay { _ = first.applyDelay(delay) }
        let transfer = Journey(legs: [walk(180, 19, 3), ride("OUT", "Outer Link", customs, k, 23.5, 8, 5), walk(0, 31.5, 0),
                                      ride("NX2", "Westgate", k, ponsonby, 34, 6, 3), walk(240, 40, 3)])
        return [first, transfer, direct("INN", "Inner Link Anticlockwise", 27, 15, 9), direct("INN", "Inner Link Anticlockwise", 42, 14, 9)]
    }
}
#endif
