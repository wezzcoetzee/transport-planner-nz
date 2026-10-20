import Foundation
import UserNotifications

/// What the notifier decided to send on a refresh tick.
enum Reminder: Equatable {
    /// A staged "leave in N minutes" reminder; 0 is "leave now".
    case lead(Int)
    /// The bus being reminded about left without the user; the journey passed in is the replacement.
    case missed
}

/// One day of reminder state. Pure so the rules can be tested without posting notifications.
///
/// Rules, so the user hears about one bus rather than every bus of the evening:
/// - Reminders start only for a journey that leaves inside the leave window.
/// - Each lead fires once per day. A replanned journey (realtime, "Next bus") inherits the leads already used.
/// - Missing the target bus sends one "missed" notice, then only "leave now" for the replacement.
/// - Choosing "Next bus" is not a miss: the next journey gets only "leave now".
/// - A second miss ends reminders for the day. The menu bar keeps counting down.
struct ReminderSchedule: Equatable {
    private(set) var targetID: String?
    private(set) var targetLeaveAt: Date?
    private(set) var fired: Set<Int> = []
    private(set) var misses = 0

    mutating func next(journeyID: String, leaveAt: Date, windowEnd: Date, leads: [Int], now: Date) -> Reminder? {
        guard misses < 2 else { return nil }
        if let id = targetID, let at = targetLeaveAt {
            if id == journeyID {
                targetLeaveAt = leaveAt // realtime may shift the same trip
            } else {
                targetID = journeyID; targetLeaveAt = leaveAt
                if now >= at {
                    misses += 1
                    guard misses < 2 else { return nil }
                    fired = Set(leads.filter { $0 > 0 })
                    return .missed
                }
            }
        } else if leaveAt > windowEnd {
            return nil
        }

        let minutesUntilLeave = leaveAt.timeIntervalSince(now) / 60
        // Take the most urgent due lead and consume the less urgent ones, so a late start is one reminder, not a burst.
        guard let lead = leads.filter({ minutesUntilLeave <= Double($0) && !fired.contains($0) }).min() else { return nil }
        fired.formUnion(leads.filter { $0 >= lead })
        targetID = journeyID; targetLeaveAt = leaveAt
        return .lead(lead)
    }

    /// The user chose the next bus. A target that never leaves makes the next journey a replacement, not a miss.
    mutating func skip(leads: [Int]) {
        guard targetID != nil else { return } // nothing reminded yet: the next bus gets the normal reminders
        targetLeaveAt = .distantFuture
        fired = Set(leads.filter { $0 > 0 })
    }
}

/// Posts leave reminders following `ReminderSchedule`, resetting each day.
@MainActor
final class LeaveNotifier {
    static let categoryID = "leave"
    static let goingAction = "going"
    static let snoozeAction = "snooze"
    static let skipAction = "skip"

    private var schedule = ReminderSchedule()
    private var dayKey = ""

    init() {
        let going = UNNotificationAction(identifier: Self.goingAction, title: "Going", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Next bus", options: [])
        let skip = UNNotificationAction(identifier: Self.skipAction, title: "Not today", options: [.destructive])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [going, snooze, skip], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Must run after the app finishes launching; asking earlier fails without a prompt.
    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Why reminders would not reach the user, or nil when they will.
    static func problem() async -> String? {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return switch (s.authorizationStatus, s.alertStyle) {
        case (.notDetermined, _): "Notifications not allowed yet"
        case (.denied, _): "Notifications are off"
        case (_, .banner): "Reminders disappear. Set the style to Persistent"
        default: nil
        }
    }

    /// Call on every refresh tick with the recommended journey. Returns the reminder due now, which the caller
    /// then posts; the schedule counts it as sent either way.
    func evaluate(journey: Journey, windowEnd: Date, leads: [Int], now: Date) -> Reminder? {
        let today = GTFSStore.dayKey(now)
        if today != dayKey { schedule = ReminderSchedule(); dayKey = today }
        return schedule.next(journeyID: journey.id, leaveAt: journey.leaveAt, windowEnd: windowEnd, leads: leads, now: now)
    }

    func post(_ reminder: Reminder, journey: Journey, now: Date) async throws {
        let content = UNMutableNotificationContent()
        let minutes = max(0, Int((journey.leaveAt.timeIntervalSince(now) / 60).rounded()))
        let isNow = reminder == .lead(0)
        switch reminder {
        case .missed: content.title = "Missed it. Next: leave \(journey.leaveAt.formatted(date: .omitted, time: .shortened))"
        case .lead: content.title = minutes <= 0 ? "Leave now" : "Leave in \(minutes) min"
        }
        content.body = journey.notificationBody
        content.sound = isNow ? .defaultCritical : .default
        content.categoryIdentifier = Self.categoryID
        content.interruptionLevel = isNow ? .timeSensitive : .active
        content.userInfo = ["journey": journey.id]
        let id = switch reminder { case .lead(let l): "leave-\(journey.id)-\(l)"; case .missed: "missed-\(journey.id)" }
        Self.clearDelivered() // with Persistent alerts, earlier reminders would otherwise pile up on screen
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func skip(leads: [Int]) { schedule.skip(leads: leads) }

    /// Takes answered or superseded reminders off the screen and out of Notification Center.
    static func clearDelivered() { UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
}

extension Journey {
    var notificationBody: String {
        guard case .ride(let route, let trip, let board, _, _, _) = firstRide.kind else { return "" }
        let dep = firstRide.departure.formatted(date: .omitted, time: .shortened)
        let arr = arriveAt.formatted(date: .omitted, time: .shortened)
        var s = "\(route.shortName) \(trip.headsign) from \(board.name) at \(dep), home \(arr)"
        if transfers > 0 { s += " (\(transfers) transfer)" }
        if let d = realtimeDelay, abs(d) >= 60 { s += d > 0 ? " · running \(d / 60) min late" : " · running \(-d / 60) min early" }
        return s
    }
}
