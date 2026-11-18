import Foundation

/// Picks the journey that best matches when the user wants to leave.
enum JourneyChooser {
    struct Preferences: Sendable {
        var preferredLeave: Date
        var now: Date
        /// Minutes of leaving late that cost as much as one minute of extra travel.
        var lateWeight = 1.0
        var earlyWeight = 0.6
        var transferPenaltyMinutes = 10.0
    }

    static func score(_ j: Journey, _ p: Preferences) -> Double {
        let offset = j.leaveAt.timeIntervalSince(p.preferredLeave) / 60
        let timing = offset >= 0 ? offset * p.lateWeight : -offset * p.earlyWeight
        return timing + j.duration / 60 * 0.5 + Double(j.transfers) * p.transferPenaltyMinutes
    }

    /// Why `pick` beats `earlier`, a bus that leaves before it: "home 4 min sooner, no transfer".
    static func reason(for pick: Journey, over earlier: Journey) -> String {
        var why: [String] = []
        let sooner = Int((earlier.arriveAt.timeIntervalSince(pick.arriveAt) / 60).rounded())
        if sooner > 0 { why.append("home \(sooner) min sooner") }
        if pick.transfers < earlier.transfers { why.append(pick.transfers == 0 ? "no transfer" : "fewer transfers") }
        // Leaving later and home no sooner, it can only win by leaving nearer the ideal time.
        if why.isEmpty { why.append("closer to your ideal time") }
        return why.joined(separator: ", ")
    }

    /// Best journey the user can still make (leave time is not already past), else nil.
    static func best(from journeys: [Journey], _ p: Preferences) -> Journey? {
        journeys
            .filter { !$0.cancelled && $0.leaveAt >= p.now.addingTimeInterval(-30) }
            .min { score($0, p) < score($1, p) }
    }
}
