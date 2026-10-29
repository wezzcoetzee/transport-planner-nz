import Foundation
import CoreLocation

/// Read side of the imported GTFS feed. All queries run on this actor.
actor GTFSStore {
    static let feedTimeZone = TimeZone(identifier: "Pacific/Auckland")!
    static let feedCalendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = feedTimeZone; return c }()

    /// "2026-10-20" for the feed's local day; keys per-day state such as reminders and skips.
    static func dayKey(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: feedTimeZone, formatOptions: [.withFullDate])
    }

    private let db: SQLiteConnection
    let path: String

    init(path: String) throws {
        self.path = path
        db = try SQLiteConnection(path: path, readOnly: true)
    }

    static func exists(at path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    // MARK: Metadata

    func meta(_ key: String) -> String? {
        try? db.query("SELECT value FROM meta WHERE key = ?", bind: [key]) { $0.text(0) }.first
    }

    var feedVersion: String? { meta("feed_version") }
    var importedAt: Date? { meta("imported_at").flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
    var feedEndDate: Int? { meta("feed_end_date").flatMap(Int.init) }

    // MARK: Stops

    func stopsNear(_ coordinate: CLLocationCoordinate2D, radiusMeters: Double) throws -> [(stop: Stop, distance: Double)] {
        let dLat = radiusMeters / 111_320
        let dLon = radiusMeters / (111_320 * cos(coordinate.latitude * .pi / 180))
        let rows = try db.query(
            """
            SELECT stop_id, stop_code, stop_name, stop_lat, stop_lon, parent_station FROM stops
            WHERE location_type = 0 AND stop_lat BETWEEN ? AND ? AND stop_lon BETWEEN ? AND ?
            """,
            bind: [coordinate.latitude - dLat, coordinate.latitude + dLat, coordinate.longitude - dLon, coordinate.longitude + dLon],
            map: Self.stop)
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return rows
            .map { ($0, $0.location.distance(from: origin)) }
            .filter { $0.1 <= radiusMeters }
            .sorted { $0.1 < $1.1 }
    }

    func stops(ids: [String]) throws -> [String: Stop] {
        guard !ids.isEmpty else { return [:] }
        let rows = try db.query(
            "SELECT stop_id, stop_code, stop_name, stop_lat, stop_lon, parent_station FROM stops WHERE stop_id IN (\(sqlPlaceholders(ids.count)))",
            bind: ids, map: Self.stop)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    private static func stop(_ s: SQLiteConnection.Statement) -> Stop {
        Stop(id: s.text(0), code: s.text(1), name: s.text(2), latitude: s.double(3), longitude: s.double(4),
             parentStation: s.isNull(5) || s.text(5).isEmpty ? nil : s.text(5))
    }

    // MARK: Calendar

    func activeServiceIDs(on day: ServiceDay) throws -> Set<String> {
        let column = ["", "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][day.weekday]
        let date = day.yyyymmdd
        var active = Set(try db.query(
            "SELECT service_id FROM calendar WHERE \(column) = 1 AND start_date <= ? AND end_date >= ?",
            bind: [date, date]) { $0.text(0) })
        for row in try db.query("SELECT service_id, exception_type FROM calendar_dates WHERE date = ?", bind: [date], map: { ($0.text(0), $0.int(1)) }) {
            if row.1 == 1 { active.insert(row.0) } else { active.remove(row.0) }
        }
        return active
    }

    // MARK: Timetable

    /// Departures from any of `stopIDs` within [from, to] service seconds on active services.
    func departures(from stopIDs: [String], between from: Int, and to: Int, services: Set<String>) throws -> [StopTime] {
        guard !stopIDs.isEmpty, !services.isEmpty else { return [] }
        return try db.query(
            """
            SELECT st.trip_id, st.stop_id, st.stop_sequence, st.arrival, st.departure
            FROM stop_times st JOIN trips t ON t.trip_id = st.trip_id
            WHERE st.stop_id IN (\(sqlPlaceholders(stopIDs.count))) AND st.departure BETWEEN ? AND ?
              AND t.service_id IN (\(sqlPlaceholders(services.count)))
            ORDER BY st.departure
            """,
            bind: stopIDs.map { $0 as SQLiteBindable } + [from, to] + services.map { $0 as SQLiteBindable },
            map: Self.stopTime)
    }

    /// All stop_times after `sequence` on each trip, keyed by trip.
    func downstreamStops(of trips: [(tripID: String, afterSequence: Int)]) throws -> [String: [StopTime]] {
        guard !trips.isEmpty else { return [:] }
        let stmt = try db.prepare("SELECT trip_id, stop_id, stop_sequence, arrival, departure FROM stop_times WHERE trip_id = ? AND stop_sequence > ? ORDER BY stop_sequence")
        var out: [String: [StopTime]] = [:]
        for t in trips {
            stmt.reset(); stmt.bind(t.tripID, t.afterSequence)
            var rows: [StopTime] = []
            while try stmt.step() { rows.append(Self.stopTime(stmt)) }
            out[t.tripID] = rows
        }
        return out
    }

    /// Stop times on trips that will later reach any destination stop today, departing within the window.
    /// Returned rows are potential boarding points for the final leg; `destinationArrival` is when that trip reaches the destination.
    func feederLegs(toward destinationStopIDs: [String], departingBetween from: Int, and to: Int, services: Set<String>)
    throws -> [(board: StopTime, alight: StopTime)] {
        guard !destinationStopIDs.isEmpty, !services.isEmpty else { return [] }
        return try db.query(
            """
            WITH reaching AS (
              SELECT st.trip_id, st.stop_id, st.stop_sequence, st.arrival, st.departure
              FROM stop_times st JOIN trips t ON t.trip_id = st.trip_id
              WHERE st.stop_id IN (\(sqlPlaceholders(destinationStopIDs.count)))
                AND st.arrival BETWEEN ? AND ?
                AND t.service_id IN (\(sqlPlaceholders(services.count)))
            )
            SELECT b.trip_id, b.stop_id, b.stop_sequence, b.arrival, b.departure,
                   r.stop_id, r.stop_sequence, r.arrival, r.departure
            FROM reaching r JOIN stop_times b ON b.trip_id = r.trip_id AND b.stop_sequence < r.stop_sequence
            WHERE b.departure BETWEEN ? AND ?
            """,
            bind: destinationStopIDs.map { $0 as SQLiteBindable } + [from, to + 3 * 3600] + services.map { $0 as SQLiteBindable } + [from, to]) { s in
                (Self.stopTime(s),
                 StopTime(tripID: s.text(0), stopID: s.text(5), sequence: s.int(6), arrival: s.int(7), departure: s.int(8)))
            }
    }

    private static func stopTime(_ s: SQLiteConnection.Statement) -> StopTime {
        StopTime(tripID: s.text(0), stopID: s.text(1), sequence: s.int(2), arrival: s.int(3), departure: s.int(4))
    }

    func trips(ids: [String]) throws -> [String: TripInfo] {
        guard !ids.isEmpty else { return [:] }
        let rows = try db.query("SELECT trip_id, route_id, trip_headsign FROM trips WHERE trip_id IN (\(sqlPlaceholders(ids.count)))", bind: ids) {
            TripInfo(id: $0.text(0), routeID: $0.text(1), headsign: $0.text(2))
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    func routes(ids: [String]) throws -> [String: Route] {
        guard !ids.isEmpty else { return [:] }
        let rows = try db.query("SELECT route_id, route_short_name, route_long_name, route_type, route_color FROM routes WHERE route_id IN (\(sqlPlaceholders(ids.count)))", bind: ids) {
            Route(id: $0.text(0), shortName: $0.text(1), longName: $0.text(2), type: $0.int(3), color: $0.text(4).isEmpty ? nil : $0.text(4))
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }
}
