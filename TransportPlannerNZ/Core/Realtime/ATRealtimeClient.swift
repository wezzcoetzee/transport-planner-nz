import Foundation
import os

/// Auckland Transport GTFS-Realtime trip updates. Requires a free subscription key from dev-portal.at.govt.nz.
struct ATRealtimeClient: Sendable {
    static let tripUpdatesURL = URL(string: "https://api.at.govt.nz/realtime/legacy/tripupdates")!
    private static let log = Logger(subsystem: "org.transportplannernz.TransportPlannerNZ", category: "realtime")

    let subscriptionKey: String
    var session: URLSession = .shared

    struct TripUpdate: Sendable {
        let tripID: String
        let cancelled: Bool
        /// (stop_sequence, delay seconds) for each reported stop, ascending by sequence.
        let stopDelays: [(sequence: Int, delay: Int)]

        /// Delay expected at `sequence`: the most recent report at or before it, else the earliest report after it.
        func delay(atSequence sequence: Int) -> Int? {
            stopDelays.last { $0.sequence <= sequence }?.delay ?? stopDelays.first?.delay
        }
    }

    enum ClientError: Error, LocalizedError {
        case http(Int)
        case unauthorized
        var errorDescription: String? {
            switch self { case .unauthorized: "AT API key rejected"; case .http(let c): "AT API HTTP \(c)" }
        }
    }

    func tripUpdates(for tripIDs: [String]) async throws -> [String: TripUpdate] {
        guard !tripIDs.isEmpty else { return [:] }
        var comps = URLComponents(url: Self.tripUpdatesURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "tripid", value: tripIDs.joined(separator: ","))]
        var req = URLRequest(url: comps.url!)
        req.setValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw ClientError.unauthorized }
        guard (200..<300).contains(code) else { throw ClientError.http(code) }
        let wanted = Set(tripIDs)
        return try Self.parse(data).filter { wanted.contains($0.key) }
    }

    /// Lenient GTFS-RT JSON parsing. AT wraps the feed in {"status","response"} and its legacy endpoint has
    /// historically returned `stop_time_update` as a single object rather than an array.
    static func parse(_ data: Data) throws -> [String: TripUpdate] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let feed = root["response"] as? [String: Any] ?? root
        let entities = feed["entity"] as? [[String: Any]] ?? []
        var out: [String: TripUpdate] = [:]
        for e in entities {
            guard let tu = e["trip_update"] as? [String: Any], let trip = tu["trip"] as? [String: Any],
                  let tripID = trip["trip_id"] as? String else { continue }
            let rel = trip["schedule_relationship"]
            let cancelled = (rel as? Int) == 3 || (rel as? String) == "CANCELED" || (rel as? String) == "CANCELLED"
            let updates: [[String: Any]] = (tu["stop_time_update"] as? [[String: Any]]) ?? (tu["stop_time_update"] as? [String: Any]).map { [$0] } ?? []
            var delays: [(Int, Int)] = []
            for u in updates {
                guard let seq = u["stop_sequence"] as? Int else { continue }
                let event = (u["departure"] as? [String: Any]) ?? (u["arrival"] as? [String: Any])
                if let d = event?["delay"] as? Int { delays.append((seq, d)) }
            }
            delays.sort { $0.0 < $1.0 }
            out[tripID] = TripUpdate(tripID: tripID, cancelled: cancelled, stopDelays: delays.map { (sequence: $0.0, delay: $0.1) })
        }
        return out
    }
}

/// Applies realtime trip updates to scheduled journeys.
enum RealtimeAdjuster {
    static func apply(_ updates: [String: ATRealtimeClient.TripUpdate], to journeys: [Journey]) -> [Journey] {
        journeys.compactMap { j in
            var j = j
            guard case .ride(_, let trip, _, _, let seq, _) = j.firstRide.kind, let u = updates[trip.id] else { return j }
            if u.cancelled { j.cancelled = true; return j }
            guard let delay = u.delay(atSequence: seq) else { return j }
            let connectionHolds = j.applyDelay(delay)
            return connectionHolds ? j : nil
        }
    }
}
