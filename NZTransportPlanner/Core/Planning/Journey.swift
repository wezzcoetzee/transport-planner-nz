import Foundation
import CoreLocation

struct Leg: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case walk(meters: Double)
        case ride(route: Route, trip: TripInfo, board: Stop, alight: Stop, boardSequence: Int, stops: Int)
    }
    let kind: Kind
    var departure: Date
    var arrival: Date

    var id: String {
        switch kind {
        case .walk: "walk-\(departure.timeIntervalSince1970)"
        case .ride(_, let trip, let board, _, _, _): "ride-\(trip.id)-\(board.id)"
        }
    }
    var duration: TimeInterval { arrival.timeIntervalSince(departure) }
    var isRide: Bool { if case .ride = kind { true } else { false } }
}

struct Journey: Hashable, Sendable, Identifiable {
    var legs: [Leg]
    /// Delay applied to the first ride from realtime data, in seconds. nil = schedule only.
    var realtimeDelay: Int? = nil
    var cancelled = false

    var id: String { legs.filter(\.isRide).map(\.id).joined(separator: "+") }
    var leaveAt: Date { legs.first!.departure }
    var arriveAt: Date { legs.last!.arrival }
    var duration: TimeInterval { arriveAt.timeIntervalSince(leaveAt) }
    var rides: [Leg] { legs.filter(\.isRide) }
    var transfers: Int { max(0, rides.count - 1) }
    var firstRide: Leg { rides.first! }
    var firstBoardStop: Stop? { if case .ride(_, _, let board, _, _, _) = firstRide.kind { board } else { nil } }
    var firstBoardSequence: Int? { if case .ride(_, _, _, _, let seq, _) = firstRide.kind { seq } else { nil } }
    var isRealtime: Bool { realtimeDelay != nil }
    /// Stops ridden through across every ride leg.
    var stopCount: Int { rides.reduce(0) { if case .ride(_, _, _, _, _, let n) = $1.kind { $0 + n } else { $0 } } }

    /// Route short names in order, e.g. "70 → EAST"
    var summary: String {
        rides.compactMap { if case .ride(let r, _, _, _, _, _) = $0.kind { r.shortName } else { nil } }.joined(separator: " → ")
    }

    /// Shift the walk to the first stop and the first ride by `seconds` (positive = late).
    /// Later legs keep their scheduled times. Returns false if the delay breaks a transfer.
    mutating func applyDelay(_ seconds: Int) -> Bool {
        realtimeDelay = seconds
        guard let rideIndex = legs.firstIndex(where: \.isRide) else { return true }
        let shift = TimeInterval(seconds)
        for i in 0...rideIndex { legs[i].departure.addTimeInterval(shift); legs[i].arrival.addTimeInterval(shift) }
        let next = rideIndex + 1
        guard next < legs.count else { return true }
        let walk = legs[next].duration
        legs[next].departure = legs[rideIndex].arrival
        legs[next].arrival = legs[rideIndex].arrival.addingTimeInterval(walk)
        guard next + 1 < legs.count else { return true }
        return legs[next].arrival <= legs[next + 1].departure
    }
}
