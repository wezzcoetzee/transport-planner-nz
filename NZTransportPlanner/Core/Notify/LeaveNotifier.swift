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
/// - Each lead fires once per day. A replanned journey (realtime, "Next") inherits the leads already used.
/// - Missing the target bus sends one "missed" notice, then only "leave now" for the replacement.
/// - Choosing "Next" is not a miss: the next journey gets only "leave now".
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
    /// Early reminders leave out Going: tapped twenty minutes out it would end the day before the leave-now moment.
    static let earlyCategoryID = "leave-early"
    /// From this many minutes out the countdown turns orange and "Going" is offered: leaving now is a real answer.
    static let soonMinutes = 10
    static let goingAction = "going"
    static let snoozeAction = "snooze"
    static let skipAction = "skip"

    private var schedule = ReminderSchedule()
    private var dayKey = ""
    /// Leave time of the last reminder on screen, so it can be taken down once that bus has gone.
    private var postedLeaveAt: Date?

    init() {
        let going = UNNotificationAction(identifier: Self.goingAction, title: "Going", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Next", options: [])
        let skip = UNNotificationAction(identifier: Self.skipAction, title: "Not today", options: []) // undone from the popover, so not destructive
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [going, snooze, skip], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.earlyCategoryID, actions: [snooze, skip], intentIdentifiers: []),
        ])
    }

    /// Must run after the app finishes launching; asking earlier fails without a prompt.
    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Why reminders would not reach the user, or nil when they will.
    static func problem() async -> String? {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return switch (s.authorizationStatus, s.alertStyle) {
        case (.notDetermined, _): nil // the system prompt is on its way (asked once both places are set)
        case (.denied, _): "Notifications are off"
        case (_, .banner): "Notifications disappear. Set the style to Persistent"
        case (_, .none): "Notifications are hidden. Set the style to Persistent"
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
        let minutes = max(0, journey.minutesUntilLeave(from: now))
        let isNow = reminder == .lead(0)
        switch reminder {
        case .missed: content.title = "Missed it. Leave at \(journey.leaveAt.formatted(date: .omitted, time: .shortened))"
        // Persistent alerts stay up, so the title carries the clock time as well as the countdown.
        case .lead: content.title = minutes <= 0 ? "Leave now" : "Leave in \(minutes) min, at \(journey.leaveAt.formatted(date: .omitted, time: .shortened))"
        }
        content.body = journey.notificationBody
        content.sound = .default // critical sounds need an Apple entitlement this ad-hoc signed app cannot have
        let offersGoing = switch reminder { case .missed: true; case .lead(let l): l <= Self.soonMinutes }
        content.categoryIdentifier = offersGoing ? Self.categoryID : Self.earlyCategoryID
        content.interruptionLevel = isNow ? .timeSensitive : .active
        content.userInfo = ["journey": journey.id]
        let id = switch reminder { case .lead(let l): "leave-\(journey.id)-\(l)"; case .missed: "missed-\(journey.id)" }
        Self.clearDelivered() // with Persistent alerts, earlier reminders would otherwise pile up on screen
        postedLeaveAt = journey.leaveAt
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func skip(leads: [Int]) { schedule.skip(leads: leads) }

    /// Takes a reminder down once its bus left over five minutes ago and nothing newer replaced it.
    func clearIfStale(now: Date) {
        guard let at = postedLeaveAt, now.timeIntervalSince(at) > 5 * 60 else { return }
        postedLeaveAt = nil
        Self.clearDelivered()
    }

    /// Takes answered or superseded reminders off the screen and out of Notification Center.
    static func clearDelivered() { UNUserNotificationCenter.current().removeAllDeliveredNotifications() }
}

extension Journey {
    /// "INN 5:08 pm from Lower Albert Street": the bus and the stop, which is what the user checks on the way out.
    var boardingLine: String {
        guard case .ride(let route, _, let board, _, _, _) = firstRide.kind else { return "" }
        return "\(route.shortName) \(boardTime.formatted(date: .omitted, time: .shortened)) from \(board.name)"
    }

    /// The first bus's time as a departure board shows it: the timetable time when it is notably late (the delay
    /// follows it), otherwise the expected time, so a small delay never reads as added twice.
    var boardTime: Date {
        isNotablyLate ? firstRide.departure.addingTimeInterval(-TimeInterval(realtimeDelay ?? 0)) : firstRide.departure
    }

    /// "home 5:23 pm, 1 transfer".
    var arrivalLine: String {
        "home \(arriveAt.formatted(date: .omitted, time: .shortened))" + (transfers > 0 ? ", \(transfers) transfer" : "")
    }

    /// "4 min late" when the first bus is three minutes or more behind; smaller shifts are already in the times shown.
    var delayNote: String? { isNotablyLate ? "\((realtimeDelay ?? 0) / 60) min late" : nil }

    /// "INN 5:08 pm from Lower Albert Street, 4 min late, home 5:23 pm": the delay belongs to the bus, not to home.
    var notificationBody: String { [boardingLine, delayNote, arrivalLine].compactMap { $0 }.joined(separator: ", ") }

    /// Whole minutes until the leave time, rounded down so a countdown never promises more time than there is.
    func minutesUntilLeave(from now: Date) -> Int { Int((leaveAt.timeIntervalSince(now) / 60).rounded(.down)) }

    /// Countdowns redraw this long after each minute boundary, so the rounded-down minute has already changed.
    static let tickOffset = 0.5

    /// A delay big enough to change plans; anything smaller is already inside the times shown.
    var isNotablyLate: Bool { (realtimeDelay ?? 0) >= 180 }
}
