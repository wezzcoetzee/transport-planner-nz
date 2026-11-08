import Foundation
import CoreLocation

/// A stop the user can walk to, with the walking time from their location.
struct AccessStop: Hashable, Sendable, Codable {
    let stop: Stop
    let walkMeters: Double
    let walkSeconds: Int
}

struct PlanRequest: Sendable {
    var originStops: [AccessStop]
    var destinationStops: [AccessStop]
    /// Earliest and latest acceptable instants to leave the origin.
    var leaveWindow: ClosedRange<Date>
    var maxTransfers = 1
    /// Slack added before a departure so a slightly early bus is not missed.
    var boardingBufferSeconds = 90
    var transferBufferSeconds = 120
    var walkMetersPerSecond = 1.3
    var maxTransferWalkMeters = 250.0
}

/// Timetable journey search over the GTFS store: direct trips plus one transfer, both service days that could be running.
struct JourneyPlanner: Sendable {
    let store: GTFSStore

    func plan(_ req: PlanRequest) async throws -> [Journey] {
        var journeys: [Journey] = []
        let tz = GTFSStore.feedTimeZone
        for offset in [0, -1] {
            let day = ServiceDay(containing: req.leaveWindow.lowerBound, timeZone: tz, dayOffset: offset)
            journeys += try await plan(req, on: day)
        }
        return Self.rank(journeys)
    }

    private func plan(_ req: PlanRequest, on day: ServiceDay) async throws -> [Journey] {
        let services = try await store.activeServiceIDs(on: day)
        guard !services.isEmpty else { return [] }

        let originByID = Dictionary(uniqueKeysWithValues: req.originStops.map { ($0.stop.id, $0) })
        let destByID = Dictionary(uniqueKeysWithValues: req.destinationStops.map { ($0.stop.id, $0) })
        guard !originByID.isEmpty, !destByID.isEmpty else { return [] }

        let minWalk = req.originStops.map(\.walkSeconds).min() ?? 0
        let maxWalk = req.originStops.map(\.walkSeconds).max() ?? 0
        let boardFrom = day.serviceSeconds(of: req.leaveWindow.lowerBound) + minWalk + req.boardingBufferSeconds
        let boardTo = day.serviceSeconds(of: req.leaveWindow.upperBound) + maxWalk + req.boardingBufferSeconds
        guard boardTo > 0 else { return [] }

        // Candidate boardings at the origin, filtered to the user's leave window.
        var boardings: [StopTime] = []
        for st in try await store.departures(from: Array(originByID.keys), between: boardFrom, and: boardTo, services: services) {
            let access = originByID[st.stopID]!
            let leaveAt = day.instant(atServiceSeconds: st.departure - access.walkSeconds - req.boardingBufferSeconds)
            if req.leaveWindow.contains(leaveAt) { boardings.append(st) }
        }
        guard !boardings.isEmpty else { return [] }

        // Keep only the earliest boarding per trip (a trip passing two of our stops).
        var bestBoardingPerTrip: [String: StopTime] = [:]
        for b in boardings where bestBoardingPerTrip[b.tripID].map({ b.departure < $0.departure }) ?? true { bestBoardingPerTrip[b.tripID] = b }
        boardings = Array(bestBoardingPerTrip.values)

        let downstream = try await store.downstreamStops(of: boardings.map { ($0.tripID, $0.sequence) })

        // One-transfer feeders: anything that reaches a destination stop, departing after our earliest boarding.
        var feedersByStop: [String: [(board: StopTime, alight: StopTime)]] = [:]
        var feederStopIDs = Set<String>()
        if req.maxTransfers >= 1 {
            let feeders = try await store.feederLegs(toward: Array(destByID.keys), departingBetween: boardFrom, and: boardTo + 2 * 3600, services: services)
            for f in feeders { feedersByStop[f.board.stopID, default: []].append(f); feederStopIDs.insert(f.board.stopID) }
        }

        // Resolve every stop we might mention, and build a proximity index for transfer walks.
        var stopIDs = Set(originByID.keys).union(destByID.keys).union(feederStopIDs)
        for list in downstream.values { for st in list { stopIDs.insert(st.stopID) } }
        let stops = try await store.stops(ids: Array(stopIDs))
        let feederGrid = ProximityGrid(stops: feederStopIDs.compactMap { stops[$0] })

        var tripIDs = Set(boardings.map(\.tripID))
        for list in feedersByStop.values { for f in list { tripIDs.insert(f.board.tripID) } }
        let trips = try await store.trips(ids: Array(tripIDs))
        let routes = try await store.routes(ids: Array(Set(trips.values.map(\.routeID))))

        func ride(_ board: StopTime, _ alight: StopTime, stopsBetween: Int) -> Leg? {
            guard let trip = trips[board.tripID], let route = routes[trip.routeID],
                  let b = stops[board.stopID], let a = stops[alight.stopID] else { return nil }
            return Leg(kind: .ride(route: route, trip: trip, board: b, alight: a, boardSequence: board.sequence, stops: stopsBetween),
                       departure: day.instant(atServiceSeconds: board.departure), arrival: day.instant(atServiceSeconds: alight.arrival))
        }
        func walk(meters: Double, seconds: Int, from: Date) -> Leg {
            Leg(kind: .walk(meters: meters), departure: from, arrival: from.addingTimeInterval(TimeInterval(seconds)))
        }

        var journeys: [Journey] = []
        for boarding in boardings {
            let access = originByID[boarding.stopID]!
            let path = downstream[boarding.tripID] ?? []
            let firstDeparture = day.instant(atServiceSeconds: boarding.departure)
            let leaveAt = firstDeparture.addingTimeInterval(TimeInterval(-access.walkSeconds - req.boardingBufferSeconds))
            let walkToStop = Leg(kind: .walk(meters: access.walkMeters), departure: leaveAt, arrival: leaveAt.addingTimeInterval(TimeInterval(access.walkSeconds)))

            // Direct
            var best: Journey?
            for (i, st) in path.enumerated() {
                guard let dest = destByID[st.stopID], let r = ride(boarding, st, stopsBetween: i + 1) else { continue }
                let j = Journey(legs: [walkToStop, r, walk(meters: dest.walkMeters, seconds: dest.walkSeconds, from: r.arrival)])
                if best.map({ j.arriveAt < $0.arriveAt }) ?? true { best = j }
            }
            if let best { journeys.append(best); continue }
            guard req.maxTransfers >= 1 else { continue }

            // One transfer: alight somewhere downstream, walk (or not) to a feeder stop, ride to the destination.
            for (i, st) in path.enumerated() where destByID[st.stopID] == nil {
                guard let here = stops[st.stopID] else { continue }
                for near in feederGrid.stops(near: here.coordinate, within: req.maxTransferWalkMeters) {
                    let walkMeters = here.location.distance(from: near.location)
                    let walkSecs = Int(walkMeters / req.walkMetersPerSecond)
                    let readyAt = st.arrival + walkSecs + req.transferBufferSeconds
                    for f in feedersByStop[near.id] ?? [] where f.board.departure >= readyAt && f.board.tripID != boarding.tripID {
                        guard let dest = destByID[f.alight.stopID],
                              let r1 = ride(boarding, st, stopsBetween: i + 1),
                              let r2 = ride(f.board, f.alight, stopsBetween: f.alight.sequence - f.board.sequence),
                              case .ride(let route1, _, _, _, _, _) = r1.kind, case .ride(let route2, _, _, _, _, _) = r2.kind,
                              route1.id != route2.id else { continue }
                        let transferWalk = walk(meters: walkMeters, seconds: walkSecs, from: r1.arrival)
                        let j = Journey(legs: [walkToStop, r1, transferWalk, r2, walk(meters: dest.walkMeters, seconds: dest.walkSeconds, from: r2.arrival)])
                        if best.map({ j.arriveAt < $0.arriveAt }) ?? true { best = j }
                    }
                }
            }
            if let best { journeys.append(best) }
        }
        return journeys
    }

    /// Pareto-prune (a journey that leaves earlier and arrives later than another is useless) and order by leave time.
    static func rank(_ journeys: [Journey]) -> [Journey] {
        let sorted = journeys.sorted { $0.leaveAt != $1.leaveAt ? $0.leaveAt > $1.leaveAt : $0.arriveAt < $1.arriveAt }
        var kept: [Journey] = []
        var bestArrival = Date.distantFuture
        for j in sorted { // leaving latest first; keep only if it arrives before anything that leaves later
            if j.arriveAt < bestArrival { kept.append(j); bestArrival = j.arriveAt }
        }
        return kept.sorted { $0.leaveAt < $1.leaveAt }
    }
}

/// Bucketed lookup of stops by coordinate for transfer matching.
struct ProximityGrid: Sendable {
    private var buckets: [Int: [Stop]] = [:]
    private let cell = 0.003 // ~330 m latitude

    init(stops: [Stop]) {
        for s in stops { buckets[key(s.latitude, s.longitude), default: []].append(s) }
    }

    private func key(_ lat: Double, _ lon: Double) -> Int {
        Int((lat / cell).rounded(.down)) &* 100_000 &+ Int((lon / cell).rounded(.down))
    }

    func stops(near c: CLLocationCoordinate2D, within meters: Double) -> [Stop] {
        let origin = CLLocation(latitude: c.latitude, longitude: c.longitude)
        var out: [Stop] = []
        for dLat in -1...1 { for dLon in -1...1 {
            let k = key(c.latitude + Double(dLat) * cell, c.longitude + Double(dLon) * cell)
            for s in buckets[k] ?? [] where s.location.distance(from: origin) <= meters { out.append(s) }
        } }
        return out
    }
}
