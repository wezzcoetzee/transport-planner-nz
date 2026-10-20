import CoreLocation

/// Where the user is relative to the office. Reminders are for walking out of the office, so they only fire there.
enum Presence: Equatable, Sendable {
    case atOffice
    case away
    /// No usable fix (location off, denied, still looking, or too vague). Reminders behave as if at the office.
    case unknown

    static let officeRadiusMeters = 500.0
    /// A Mac locates itself by Wi-Fi; a fix vaguer than this cannot tell the office from the suburb around it.
    static let maxAccuracyMeters = 1_000.0

    init(location: CLLocation?, office: Place?) {
        guard let location, let office, (0...Self.maxAccuracyMeters).contains(location.horizontalAccuracy) else {
            self = .unknown; return
        }
        let distance = location.distance(from: CLLocation(latitude: office.latitude, longitude: office.longitude))
        self = distance <= Self.officeRadiusMeters + location.horizontalAccuracy ? .atOffice : .away
    }
}

/// Streams the Mac's location. Asks for permission on first start; reports `nil` while permission is denied.
@MainActor
final class LocationMonitor {
    private var task: Task<Void, Never>?

    func start(onUpdate: @escaping @MainActor (CLLocation?) -> Void, onError: @escaping @MainActor (Error) -> Void) {
        task?.cancel()
        task = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally { onUpdate(nil) }
                    else if let location = update.location { onUpdate(location) }
                }
            } catch {
                onError(error)
            }
        }
    }
}
