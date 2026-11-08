import Foundation

/// GTFS times are "HH:MM:SS" measured from noon-minus-12h of the service day and may exceed 24:00:00.
/// We store them as seconds since the service day's nominal midnight.
enum GTFSTime {
    static func seconds(from text: Substring) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    static func seconds(from text: String) -> Int? { seconds(from: Substring(text)) }

    static func clock(_ seconds: Int) -> String {
        let h = (seconds / 3600) % 24, m = (seconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }
}

/// A GTFS service day in the feed's timezone. Trips that run past midnight belong to the previous day.
struct ServiceDay: Hashable, Sendable {
    let date: DateComponents // year, month, day only
    let midnight: Date
    let timeZone: TimeZone

    init(containing instant: Date, timeZone: TimeZone, dayOffset: Int = 0) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var start = cal.startOfDay(for: instant)
        if dayOffset != 0 { start = cal.date(byAdding: .day, value: dayOffset, to: start)! }
        self.timeZone = timeZone
        self.midnight = start
        self.date = cal.dateComponents([.year, .month, .day, .weekday], from: start)
    }

    /// yyyymmdd as used by calendar.txt
    var yyyymmdd: Int { date.year! * 10000 + date.month! * 100 + date.day! }

    /// 1 = Sunday ... 7 = Saturday (Foundation convention)
    var weekday: Int { date.weekday! }

    func instant(atServiceSeconds seconds: Int) -> Date { midnight.addingTimeInterval(TimeInterval(seconds)) }

    func serviceSeconds(of instant: Date) -> Int { Int(instant.timeIntervalSince(midnight).rounded()) }
}
