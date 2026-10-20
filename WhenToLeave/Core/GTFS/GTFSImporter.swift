import Foundation
import os

/// Downloads the public AT GTFS zip and builds a fresh SQLite database next to the live one, then swaps it in.
actor GTFSImporter {
    static let feedURL = URL(string: "https://gtfs.at.govt.nz/gtfs.zip")!
    private static let log = Logger(subsystem: "org.transportplannernz.WhenToLeave", category: "import")

    enum Phase: Sendable, Equatable {
        case idle, downloading(Double), extracting, importing(String), indexing, done, failed(String)
        var label: String {
            switch self {
            case .idle: "Idle"
            case .downloading(let p): p > 0 ? "Downloading \(Int(p * 100))%" : "Downloading"
            case .extracting: "Extracting"
            case .importing(let f): "Importing \(f)"
            case .indexing: "Indexing"
            case .done: "Up to date"
            case .failed(let m): "Failed: \(m)"
            }
        }
    }

    let destinationPath: String
    private(set) var phase: Phase = .idle
    private var onPhase: (@Sendable (Phase) -> Void)?

    init(destinationPath: String) { self.destinationPath = destinationPath }

    func observe(_ handler: @escaping @Sendable (Phase) -> Void) { onPhase = handler }

    private func set(_ p: Phase) { phase = p; onPhase?(p) }

    /// Returns the ETag of the remote feed, used to skip unchanged downloads.
    static func remoteETag() async -> String? {
        var req = URLRequest(url: feedURL); req.httpMethod = "HEAD"; req.timeoutInterval = 15
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        return (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
    }

    func run(etag: String?) async throws {
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wtl-gtfs-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            set(.downloading(0))
            let zip = tmp.appendingPathComponent("gtfs.zip")
            let (downloaded, _) = try await URLSession.shared.download(from: Self.feedURL)
            try FileManager.default.moveItem(at: downloaded, to: zip)

            set(.extracting)
            let extracted = tmp.appendingPathComponent("feed")
            try Self.unzip(zip, to: extracted)

            let stagingPath = destinationPath + ".staging"
            try? FileManager.default.removeItem(atPath: stagingPath)
            try build(from: extracted, to: stagingPath, etag: etag)

            let live = URL(fileURLWithPath: destinationPath), staged = URL(fileURLWithPath: stagingPath)
            if FileManager.default.fileExists(atPath: destinationPath) {
                _ = try FileManager.default.replaceItemAt(live, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: live)
            }
            set(.done)
        } catch {
            Self.log.error("GTFS import failed: \(error)")
            set(.failed(String(describing: error)))
            throw error
        }
    }

    private static func unzip(_ zip: URL, to dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw SQLiteError(message: "ditto failed (\(p.terminationStatus))") }
    }

    func build(from dir: URL, to path: String, etag: String?) throws {
        let db = try SQLiteConnection(path: path)
        try db.exec("""
        PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF; PRAGMA temp_store = MEMORY; PRAGMA cache_size = -200000;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE stops (stop_id TEXT PRIMARY KEY, stop_code TEXT, stop_name TEXT, stop_lat REAL, stop_lon REAL, location_type INTEGER, parent_station TEXT);
        CREATE TABLE routes (route_id TEXT PRIMARY KEY, route_short_name TEXT, route_long_name TEXT, route_type INTEGER, route_color TEXT);
        CREATE TABLE trips (trip_id TEXT PRIMARY KEY, route_id TEXT, service_id TEXT, trip_headsign TEXT, direction_id INTEGER);
        CREATE TABLE stop_times (trip_id TEXT, stop_id TEXT, stop_sequence INTEGER, arrival INTEGER, departure INTEGER);
        CREATE TABLE calendar (service_id TEXT PRIMARY KEY, monday INTEGER, tuesday INTEGER, wednesday INTEGER, thursday INTEGER, friday INTEGER, saturday INTEGER, sunday INTEGER, start_date INTEGER, end_date INTEGER);
        CREATE TABLE calendar_dates (service_id TEXT, date INTEGER, exception_type INTEGER);
        """)

        try importTable(db, dir, "stops.txt", "INSERT OR REPLACE INTO stops VALUES (?,?,?,?,?,?,?)",
                        columns: ["stop_id", "stop_code", "stop_name", "stop_lat", "stop_lon", "location_type", "parent_station"]) { r in
            [r[0], r[1], r[2], Double(r[3]) ?? 0, Double(r[4]) ?? 0, Int(r[5]) ?? 0, r[6]]
        }
        try importTable(db, dir, "routes.txt", "INSERT OR REPLACE INTO routes VALUES (?,?,?,?,?)",
                        columns: ["route_id", "route_short_name", "route_long_name", "route_type", "route_color"]) { r in
            [r[0], r[1], r[2], Int(r[3]) ?? 3, r[4]]
        }
        try importTable(db, dir, "trips.txt", "INSERT OR REPLACE INTO trips VALUES (?,?,?,?,?)",
                        columns: ["trip_id", "route_id", "service_id", "trip_headsign", "direction_id"]) { r in
            [r[0], r[1], r[2], r[3], Int(r[4]) ?? 0]
        }
        try importTable(db, dir, "calendar.txt", "INSERT OR REPLACE INTO calendar VALUES (?,?,?,?,?,?,?,?,?,?)",
                        columns: ["service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "start_date", "end_date"]) { r in
            [r[0]] + r[1...9].map { Int($0) ?? 0 }
        }
        try importTable(db, dir, "calendar_dates.txt", "INSERT INTO calendar_dates VALUES (?,?,?)",
                        columns: ["service_id", "date", "exception_type"]) { r in [r[0], Int(r[1]) ?? 0, Int(r[2]) ?? 0] }
        try importTable(db, dir, "stop_times.txt", "INSERT INTO stop_times VALUES (?,?,?,?,?)",
                        columns: ["trip_id", "stop_id", "stop_sequence", "arrival_time", "departure_time"]) { r in
            let arr = GTFSTime.seconds(from: r[3]) ?? -1
            let dep = GTFSTime.seconds(from: r[4]) ?? arr
            return [r[0], r[1], Int(r[2]) ?? 0, arr < 0 ? dep : arr, dep]
        }

        set(.indexing)
        try db.exec("""
        CREATE INDEX idx_st_stop_dep ON stop_times (stop_id, departure);
        CREATE INDEX idx_st_trip_seq ON stop_times (trip_id, stop_sequence);
        CREATE INDEX idx_trips_service ON trips (service_id);
        CREATE INDEX idx_stops_lat ON stops (stop_lat);
        """)

        var info: [String: String] = ["imported_at": String(Date().timeIntervalSince1970)]
        if let etag { info["etag"] = etag }
        if var feed = try? CSVReader(url: dir.appendingPathComponent("feed_info.txt")), let row = feed.next() {
            if let i = feed.index(of: "feed_version") { info["feed_version"] = row[i] }
            if let i = feed.index(of: "feed_end_date") { info["feed_end_date"] = row[i] }
        }
        let insertMeta = try db.prepare("INSERT INTO meta VALUES (?, ?)")
        for (k, v) in info { insertMeta.reset(); insertMeta.bind(k, v); _ = try insertMeta.step() }
    }

    private func importTable(_ db: SQLiteConnection, _ dir: URL, _ file: String, _ insert: String,
                             columns: [String], map: ([String]) -> [SQLiteBindable]) throws {
        set(.importing(file))
        var reader = try CSVReader(url: dir.appendingPathComponent(file))
        let indices = columns.map { reader.index(of: $0) }
        let stmt = try db.prepare(insert)
        try db.exec("BEGIN")
        var n = 0
        while let row = reader.next() {
            let picked = indices.map { $0.map { $0 < row.count ? row[$0] : "" } ?? "" }
            stmt.reset()
            for (i, v) in map(picked).enumerated() { v.bind(to: stmt, index: Int32(i + 1)) }
            _ = try stmt.step()
            n += 1
            if n % 200_000 == 0 { try db.exec("COMMIT; BEGIN") }
        }
        try db.exec("COMMIT")
        Self.log.info("Imported \(n) rows from \(file)")
    }
}
