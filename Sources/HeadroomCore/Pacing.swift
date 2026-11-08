import Foundation

/// Values are percentage points of the full weekly allowance, not credits.
public struct PacingReading {
    public let dailyPace: Double
    public let todayRemaining: Double
    public let todayBudget: Double
    public var todayRemainingPercent: Double {
        todayBudget > 0 ? min(100, max(0, todayRemaining / todayBudget * 100)) : 0
    }
}

/// One local daily anchor, rather than a growing usage history.
public struct PacingPlanner: Codable {
    private struct Anchor: Codable {
        let date: Date
        let reset: Date
        let remaining: Double
        let reserve: Double
        let timeZone: String
        let targetAtDayEnd: Double
    }
    private var anchor: Anchor?
    private var lastRemaining: Double?

    public init() {}

    public mutating func update(remaining: Double, reset: Date, now: Date,
                                reserve: Double, calendar: Calendar = .current) -> PacingReading? {
        let secondsLeft = reset.timeIntervalSince(now)
        guard remaining.isFinite, reserve.isFinite, secondsLeft.isFinite,
              secondsLeft > 0, secondsLeft <= 7 * 86_400 + 300,
              let day = calendar.dateInterval(of: .day, for: now) else {
            anchor = nil
            lastRemaining = nil
            return nil
        }
        let remaining = min(100, max(0, remaining))
        let reserve = min(100, max(0, reserve))
        let spendable = max(0, remaining - reserve)
        if anchor == nil || anchor!.reset != reset || anchor!.reserve != reserve ||
            anchor!.timeZone != calendar.timeZone.identifier || !day.contains(anchor!.date) ||
            anchor!.date > now || remaining > (lastRemaining ?? anchor!.remaining) + 0.001 {
            let todaySeconds = min(reset, day.end).timeIntervalSince(now)
            let budget = spendable * todaySeconds / secondsLeft
            anchor = Anchor(date: now, reset: reset, remaining: remaining, reserve: reserve,
                            timeZone: calendar.timeZone.identifier, targetAtDayEnd: remaining - budget)
        }
        lastRemaining = remaining
        guard let anchor else { return nil }
        return PacingReading(dailyPace: min(spendable, spendable * 86_400 / secondsLeft),
                             todayRemaining: min(spendable, max(0, remaining - anchor.targetAtDayEnd)),
                             todayBudget: max(0, anchor.remaining - anchor.targetAtDayEnd))
    }
}
