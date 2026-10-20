import Foundation
import CoreLocation

struct Stop: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double
    let parentStation: String?

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
}

struct Route: Hashable, Sendable {
    let id: String
    let shortName: String
    let longName: String
    let type: Int  // GTFS route_type: 2 rail, 3 bus, 4 ferry
    let color: String?

    var modeName: String {
        switch type { case 2: "Train"; case 4: "Ferry"; default: "Bus" }
    }
    var symbolName: String {
        switch type { case 2: "tram.fill"; case 4: "ferry.fill"; default: "bus.fill" }
    }
}

struct TripInfo: Hashable, Sendable {
    let id: String
    let routeID: String
    let headsign: String
}

/// One row of stop_times for a trip, in service seconds.
struct StopTime: Hashable, Sendable {
    let tripID: String
    let stopID: String
    let sequence: Int
    let arrival: Int
    let departure: Int
}
