import Foundation
import MapKit

/// Keyless fallback: Apple Maps transit ETA between two places. Used when the GTFS database is unavailable
/// or produces no journeys, and always offered as an "open in Maps" escape hatch.
enum AppleTransitFallback {
    struct Estimate: Sendable, Hashable {
        let departure: Date
        let arrival: Date
        var travelTime: TimeInterval { arrival.timeIntervalSince(departure) }
    }

    static func estimate(from origin: Place, to destination: Place, departingAt date: Date) async throws -> Estimate {
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        req.transportType = .transit
        req.departureDate = date
        let eta = try await MKDirections(request: req).calculateETA()
        return Estimate(departure: eta.expectedDepartureDate, arrival: eta.expectedArrivalDate)
    }

    @MainActor
    static func openInMaps(from origin: Place, to destination: Place) {
        let src = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude), address: nil)
        src.name = origin.name
        let dst = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        dst.name = destination.name
        MKMapItem.openMaps(with: [src, dst], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
    }
}
