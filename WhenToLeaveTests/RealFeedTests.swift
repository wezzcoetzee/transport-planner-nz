import Testing
import Foundation
import CoreLocation

/// Opt-in end-to-end check against a real AT feed. Runs only when the feed has been extracted to `realFeedDir`:
///   curl -o /tmp/at_gtfs.zip https://gtfs.at.govt.nz/gtfs.zip && mkdir -p /tmp/at_gtfs && unzip -o /tmp/at_gtfs.zip -d /tmp/at_gtfs
struct RealFeedTests {
    static let realFeedDir = "/tmp/at_gtfs"

    @Test(.enabled(if: FileManager.default.fileExists(atPath: realFeedDir + "/stop_times.txt")))
    func importsAndPlansRealCommute() async throws {
        let dir = URL(fileURLWithPath: Self.realFeedDir)
        let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent("wtl-real-\(UUID()).sqlite").path
        let t0 = Date()
        try await GTFSImporter(destinationPath: dbPath).build(from: dir, to: dbPath, etag: nil)
        print("IMPORT took \(Date().timeIntervalSince(t0))s, size \((try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int) ?? 0) bytes")

        let store = try GTFSStore(path: dbPath)
        let office = CLLocationCoordinate2D(latitude: -36.8467, longitude: 174.7659) // Queen St / Victoria St
        let home = CLLocationCoordinate2D(latitude: -36.8549, longitude: 174.7455)   // Ponsonby Rd / Franklin Rd
        let origin = try await store.stopsNear(office, radiusMeters: 500).map { AccessStop(stop: $0.stop, walkMeters: $0.distance * 1.3, walkSeconds: Int($0.distance * 1.3 / 1.3)) }
        let dest = try await store.stopsNear(home, radiusMeters: 500).map { AccessStop(stop: $0.stop, walkMeters: $0.distance * 1.3, walkSeconds: Int($0.distance * 1.3 / 1.3)) }
        print("origin stops \(origin.count), dest stops \(dest.count)")
        #expect(!origin.isEmpty && !dest.isEmpty)

        let tz = GTFSStore.feedTimeZone
        let day = ServiceDay(containing: Date(timeIntervalSince1970: 1_788_912_000), timeZone: tz) // Wed 2026-09-09
        let window = day.instant(atServiceSeconds: 16 * 3600 + 45 * 60)...day.instant(atServiceSeconds: 17 * 3600 + 30 * 60)
        let t1 = Date()
        let journeys = try await JourneyPlanner(store: store).plan(PlanRequest(originStops: origin, destinationStops: dest, leaveWindow: window))
        print("PLAN took \(Date().timeIntervalSince(t1))s, \(journeys.count) journeys")
        let f = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: tz)
        for j in journeys {
            print("  leave \(j.leaveAt.formatted(f)) → home \(j.arriveAt.formatted(f))  \(j.summary)  transfers=\(j.transfers)  \(Int(j.duration/60))min")
        }
        #expect(!journeys.isEmpty)
        let prefs = JourneyChooser.Preferences(preferredLeave: day.instant(atServiceSeconds: 17 * 3600), now: window.lowerBound)
        let best = JourneyChooser.best(from: journeys, prefs)
        print("BEST: \(best.map { "\($0.leaveAt.formatted(f)) \($0.summary) \($0.notificationBody)" } ?? "none")")
        #expect(best != nil)
    }
}
