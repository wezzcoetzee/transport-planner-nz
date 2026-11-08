import Testing
import CoreLocation
import Foundation

/// Builds a tiny GTFS feed on disk, imports it through the real importer path (minus download), and plans over it.
struct PlannerTests {
    static let tz = TimeZone(identifier: "Pacific/Auckland")!

    @Test func parsesGTFSTimesPastMidnight() {
        #expect(GTFSTime.seconds(from: "17:05:30") == 17 * 3600 + 5 * 60 + 30)
        #expect(GTFSTime.seconds(from: "25:10:00") == 25 * 3600 + 600)
        #expect(GTFSTime.seconds(from: "bad") == nil)
    }

    @Test func csvHandlesQuotesAndCRLF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).csv")
        try "a,b,c\r\n1,\"x, y\",\"he said \"\"hi\"\"\"\r\n2,,\r\n".write(to: url, atomically: true, encoding: .utf8)
        var r = try CSVReader(url: url)
        #expect(r.header == ["a", "b", "c"])
        #expect(r.next() == ["1", "x, y", "he said \"hi\""])
        #expect(r.next() == ["2", "", ""])
        #expect(r.next() == nil)
    }

    @Test func plansDirectAndTransferJourneys() async throws {
        let store = try await Fixture.build()
        let day = ServiceDay(containing: Fixture.aWeekday, timeZone: Self.tz)
        #expect(try await store.activeServiceIDs(on: day) == ["WK"])

        let stops = try await store.stops(ids: ["A", "B", "C", "D", "E"])
        let origin = [AccessStop(stop: stops["A"]!, walkMeters: 300, walkSeconds: 240)]
        let dest = [AccessStop(stop: stops["D"]!, walkMeters: 200, walkSeconds: 150)]
        let window = day.instant(atServiceSeconds: 16 * 3600 + 40 * 60)...day.instant(atServiceSeconds: 17 * 3600 + 30 * 60)
        let req = PlanRequest(originStops: origin, destinationStops: dest, leaveWindow: window, boardingBufferSeconds: 60)
        let journeys = try await JourneyPlanner(store: store).plan(req)

        let direct = journeys.first { $0.transfers == 0 }
        let viaTransfer = journeys.first { $0.transfers == 1 }
        #expect(direct != nil, "trip T1 runs A→D directly")
        #expect(viaTransfer != nil, "trip T2 (A→B→C) connects to T3 (C→D)")
        // Leave = 17:00 departure - 4 min walk - 1 min buffer
        #expect(direct?.leaveAt == day.instant(atServiceSeconds: 17 * 3600 - 300))
        #expect(direct?.arriveAt == day.instant(atServiceSeconds: 17 * 3600 + 20 * 60 + 150))
        // Trip T4 leaves 16:30, before the window: excluded
        #expect(!journeys.contains { $0.firstRide.departure == day.instant(atServiceSeconds: 16 * 3600 + 30 * 60) })
    }

    @Test func chooserPrefersClosestToIdealAndSkipsPast() async throws {
        let store = try await Fixture.build()
        let day = ServiceDay(containing: Fixture.aWeekday, timeZone: Self.tz)
        let stops = try await store.stops(ids: ["A", "D"])
        let req = PlanRequest(originStops: [AccessStop(stop: stops["A"]!, walkMeters: 0, walkSeconds: 0)],
                              destinationStops: [AccessStop(stop: stops["D"]!, walkMeters: 0, walkSeconds: 0)],
                              leaveWindow: day.instant(atServiceSeconds: 16 * 3600)...day.instant(atServiceSeconds: 18 * 3600),
                              maxTransfers: 0, boardingBufferSeconds: 0)
        let journeys = try await JourneyPlanner(store: store).plan(req)
        #expect(journeys.count == 2) // T4 at 16:30 and T1 at 17:00
        let prefs = JourneyChooser.Preferences(preferredLeave: day.instant(atServiceSeconds: 16 * 3600 + 35 * 60), now: day.instant(atServiceSeconds: 16 * 3600))
        #expect(JourneyChooser.best(from: journeys, prefs)?.firstRide.departure == day.instant(atServiceSeconds: 16 * 3600 + 30 * 60))
        let later = JourneyChooser.Preferences(preferredLeave: prefs.preferredLeave, now: day.instant(atServiceSeconds: 16 * 3600 + 45 * 60))
        #expect(JourneyChooser.best(from: journeys, later)?.firstRide.departure == day.instant(atServiceSeconds: 17 * 3600))
    }

    @Test func remindersFireEachLeadOnceAndSwallowStaleOnes() {
        let leave = Date(timeIntervalSince1970: 100_000)
        var s = ReminderSchedule()
        func tick(_ minutes: Double, _ id: String = "a") -> Reminder? {
            s.next(journeyID: id, leaveAt: leave, windowEnd: leave, leads: [10, 5, 0], now: leave.addingTimeInterval(-minutes * 60))
        }
        #expect(tick(25) == nil)
        #expect(tick(9.5) == .lead(10))
        #expect(tick(7) == nil)
        #expect(tick(4.75) == .lead(5))
        // A replan before leaving keeps the leads already used.
        #expect(tick(3, "b") == nil)
        #expect(tick(-0.2, "b") == .lead(0))
        #expect(tick(-3, "b") == nil)
        // Starting late skips straight to the most urgent lead.
        s = ReminderSchedule()
        #expect(tick(4) == .lead(5))
        #expect(tick(3) == nil)
    }

    @Test func remindersStayQuietOutsideWindowAndAfterTwoMisses() {
        let leads = [10, 5, 0]
        let t0 = Date(timeIntervalSince1970: 100_000)
        let windowEnd = t0
        var s = ReminderSchedule()
        // A bus after the window never starts reminders.
        #expect(s.next(journeyID: "late", leaveAt: t0 + 600, windowEnd: windowEnd, leads: leads, now: t0 + 300) == nil)

        s = ReminderSchedule()
        #expect(s.next(journeyID: "a", leaveAt: t0, windowEnd: windowEnd, leads: leads, now: t0) == .lead(0))
        // Missed: one notice, then only "leave now" for the replacement, even though it is outside the window.
        #expect(s.next(journeyID: "b", leaveAt: t0 + 900, windowEnd: windowEnd, leads: leads, now: t0 + 60) == .missed)
        #expect(s.next(journeyID: "b", leaveAt: t0 + 900, windowEnd: windowEnd, leads: leads, now: t0 + 400) == nil)
        #expect(s.next(journeyID: "b", leaveAt: t0 + 900, windowEnd: windowEnd, leads: leads, now: t0 + 900) == .lead(0))
        // Second miss: quiet for the rest of the day.
        #expect(s.next(journeyID: "c", leaveAt: t0 + 1800, windowEnd: windowEnd, leads: leads, now: t0 + 1000) == nil)
        #expect(s.next(journeyID: "c", leaveAt: t0 + 1800, windowEnd: windowEnd, leads: leads, now: t0 + 1800) == nil)
    }

    @Test func choosingNextBusIsNotAMiss() {
        let leads = [10, 5, 0]
        let t0 = Date(timeIntervalSince1970: 100_000)
        var s = ReminderSchedule()
        #expect(s.next(journeyID: "a", leaveAt: t0, windowEnd: t0, leads: leads, now: t0) == .lead(0))
        s.skip(leads: leads)
        #expect(s.next(journeyID: "b", leaveAt: t0 + 900, windowEnd: t0, leads: leads, now: t0 + 30) == nil)
        #expect(s.next(journeyID: "b", leaveAt: t0 + 900, windowEnd: t0, leads: leads, now: t0 + 900) == .lead(0))
        s.skip(leads: leads)
        #expect(s.next(journeyID: "c", leaveAt: t0 + 1800, windowEnd: t0, leads: leads, now: t0 + 1800) == .lead(0))
        #expect(s.misses == 0)
    }

    @Test func presenceTellsOfficeFromHomeAndIgnoresVagueFixes() {
        let office = Place(name: "Office", latitude: 0.0, longitude: 0.0)
        func fix(_ lat: Double, _ lon: Double, accuracy: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: lat, longitude: lon), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: .now)
        }
        #expect(Presence(location: fix(0.0003, 0.0004, accuracy: 65), office: office) == .atOffice)
        #expect(Presence(location: fix(0.0, 0.1, accuracy: 65), office: office) == .away) // Synthetic point about 11 km east
        #expect(Presence(location: fix(0.0, 0.1, accuracy: 5_000), office: office) == .unknown)
        #expect(Presence(location: nil, office: office) == .unknown)
        #expect(Presence(location: fix(0.0003, 0.0004, accuracy: 65), office: nil) == .unknown)
    }

    @Test func realtimeDelayShiftsLeaveTimeAndCancelsTrips() throws {
        let json = """
        {"status":"OK","response":{"header":{},"entity":[
          {"id":"1","trip_update":{"trip":{"trip_id":"T1","schedule_relationship":0},
             "stop_time_update":{"stop_sequence":1,"stop_id":"A","departure":{"delay":180,"time":0}}}},
          {"id":"2","trip_update":{"trip":{"trip_id":"T4","schedule_relationship":3},"stop_time_update":[]}}
        ]}}
        """.data(using: .utf8)!
        let updates = try ATRealtimeClient.parse(json)
        #expect(updates["T1"]?.delay(atSequence: 2) == 180)
        #expect(updates["T4"]?.cancelled == true)

        let route = Route(id: "R", shortName: "70", longName: "", type: 3, color: nil)
        let a = Stop(id: "A", code: "1", name: "A", latitude: 0, longitude: 0, parentStation: nil)
        let d = Stop(id: "D", code: "4", name: "D", latitude: 0, longitude: 0, parentStation: nil)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func journey(_ trip: String) -> Journey {
            Journey(legs: [
                Leg(kind: .walk(meters: 100), departure: t0, arrival: t0 + 120),
                Leg(kind: .ride(route: route, trip: TripInfo(id: trip, routeID: "R", headsign: "x"), board: a, alight: d, boardSequence: 1, stops: 3), departure: t0 + 120, arrival: t0 + 1200),
                Leg(kind: .walk(meters: 50), departure: t0 + 1200, arrival: t0 + 1260),
            ])
        }
        let adjusted = RealtimeAdjuster.apply(updates, to: [journey("T1"), journey("T4")])
        #expect(adjusted[0].leaveAt == t0 + 180)
        #expect(adjusted[0].arriveAt == t0 + 1260 + 180)
        #expect(adjusted[0].realtimeDelay == 180)
        #expect(adjusted[1].cancelled)
    }
}

enum Fixture {
    /// Wednesday 2026-09-09 12:00 NZST
    static let aWeekday = Date(timeIntervalSince1970: 1_788_912_000)

    static func build() async throws -> GTFSStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wtl-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ name: String, _ body: String) throws { try body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        try write("stops.txt", """
        stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type,parent_station
        A,1,Office Stop,-36.8500,174.7600,0,
        B,2,Midway,-36.8600,174.7700,0,
        C,3,Interchange,-36.8700,174.7800,0,
        D,4,Home Stop,-36.8800,174.7900,0,
        E,5,Elsewhere,-36.9000,174.8000,0,
        """)
        try write("routes.txt", "route_id,route_short_name,route_long_name,route_type,route_color\nR1,70,Direct,3,\nR2,27,Feeder,3,\nR3,NX1,Connector,3,\n")
        try write("trips.txt", """
        route_id,service_id,trip_id,trip_headsign,direction_id
        R1,WK,T1,Home,0
        R2,WK,T2,Interchange,0
        R3,WK,T3,Home,0
        R1,WK,T4,Home,0
        R1,WE,T5,Home,0
        """)
        try write("calendar.txt", "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\nWK,1,1,1,1,1,0,0,20260101,20261231\nWE,0,0,0,0,0,1,1,20260101,20261231\n")
        try write("calendar_dates.txt", "service_id,date,exception_type\n")
        try write("stop_times.txt", """
        trip_id,arrival_time,departure_time,stop_id,stop_sequence
        T1,17:00:00,17:00:00,A,1
        T1,17:10:00,17:10:00,B,2
        T1,17:20:00,17:20:00,D,3
        T2,17:05:00,17:05:00,A,1
        T2,17:12:00,17:12:00,B,2
        T2,17:18:00,17:18:00,C,3
        T2,17:40:00,17:40:00,E,4
        T3,17:25:00,17:25:00,C,1
        T3,17:35:00,17:35:00,D,2
        T4,16:30:00,16:30:00,A,1
        T4,16:50:00,16:50:00,D,2
        T5,17:00:00,17:00:00,A,1
        T5,17:20:00,17:20:00,D,2
        """)
        try write("feed_info.txt", "feed_publisher_name,feed_version,feed_end_date\nTest,fixture-1,20261231\n")
        let dbPath = dir.appendingPathComponent("gtfs.sqlite").path
        try await GTFSImporter(destinationPath: dbPath).build(from: dir, to: dbPath, etag: nil)
        return try GTFSStore(path: dbPath)
    }
}
