import Foundation
import CoreLocation

struct Place: Codable, Hashable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct AppSettings: Codable, Hashable, Sendable {
    var office: Place?
    var home: Place?
    /// Minutes after midnight the user would ideally walk out the door.
    var preferredLeaveMinutes = 17 * 60
    /// How far either side of the preferred time is acceptable.
    var earliestLeaveOffsetMinutes = 20
    var latestLeaveOffsetMinutes = 30
    var stopSearchRadiusMeters = 600.0
    var walkMetersPerSecond = 1.3
    var boardingBufferSeconds = 90
    var maxTransfers = 1
    /// Minutes before "leave now" at which to notify. 0 = the moment to leave.
    var reminderLeadMinutes = [10, 5, 0]
    /// Foundation weekday numbers (1 = Sunday). Defaults to Mon–Fri.
    var activeWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    var atSubscriptionKey = ""
    var excludedStopIDs: Set<String> = []
    var launchAtLogin = false

    var isConfigured: Bool { office != nil && home != nil }

    func preferredLeave(on date: Date, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.startOfDay(for: date).addingTimeInterval(TimeInterval(preferredLeaveMinutes * 60))
    }

    func leaveWindow(on date: Date, in tz: TimeZone) -> ClosedRange<Date> {
        let p = preferredLeave(on: date, in: tz)
        return p.addingTimeInterval(-Double(earliestLeaveOffsetMinutes) * 60)...p.addingTimeInterval(Double(latestLeaveOffsetMinutes) * 60)
    }
}

/// UserDefaults-backed store for `AppSettings`.
enum SettingsStore {
    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    static func save(_ s: AppSettings) {
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: key)
    }
}
