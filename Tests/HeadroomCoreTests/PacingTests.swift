import XCTest
@testable import HeadroomCore

final class PacingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testTodayCountsDownWhileTomorrowRebalances() throws {
        var planner = PacingPlanner()
        let now = date("2026-11-09T00:00:00Z"), reset = date("2026-11-13T00:00:00Z")
        let start = try XCTUnwrap(planner.update(remaining: 60, reset: reset, now: now, reserve: 0, calendar: calendar))
        XCTAssertEqual(start.dailyPace, 15, accuracy: 0.001)
        XCTAssertEqual(start.todayRemaining, 15, accuracy: 0.001)
        XCTAssertEqual(start.todayRemainingPercent, 100, accuracy: 0.001)
        let later = try XCTUnwrap(planner.update(remaining: 55, reset: reset, now: now.addingTimeInterval(12 * 3600), reserve: 0, calendar: calendar))
        XCTAssertEqual(later.todayRemaining, 10, accuracy: 0.001)
        XCTAssertEqual(later.todayRemainingPercent, 100 * 10 / 15, accuracy: 0.001)
        XCTAssertEqual(later.dailyPace, 55 / 3.5, accuracy: 0.001)
        let tomorrow = try XCTUnwrap(planner.update(remaining: 55, reset: reset, now: now.addingTimeInterval(86_400), reserve: 0, calendar: calendar))
        XCTAssertEqual(tomorrow.todayRemaining, 55 / 3, accuracy: 0.001)
        XCTAssertEqual(tomorrow.todayRemainingPercent, 100, accuracy: 0.001)
    }

    func testOverspendingDoesNotImmediatelyRefillToday() throws {
        var planner = PacingPlanner()
        let now = date("2026-11-09T00:00:00Z"), reset = date("2026-11-13T00:00:00Z")
        _ = planner.update(remaining: 60, reset: reset, now: now, reserve: 0, calendar: calendar)
        let later = try XCTUnwrap(planner.update(remaining: 30, reset: reset, now: now.addingTimeInterval(3600), reserve: 0, calendar: calendar))
        XCTAssertEqual(later.todayRemaining, 0)
        XCTAssertEqual(later.todayRemainingPercent, 0)
        let tomorrow = try XCTUnwrap(planner.update(remaining: 30, reset: reset, now: now.addingTimeInterval(86_400), reserve: 0, calendar: calendar))
        XCTAssertEqual(tomorrow.dailyPace, 10, accuracy: 0.001)
    }

    func testPartialDayReserveAndPersistence() throws {
        var planner = PacingPlanner()
        let now = date("2026-11-09T12:00:00Z"), reset = date("2026-11-13T00:00:00Z")
        let start = try XCTUnwrap(planner.update(remaining: 60, reset: reset, now: now, reserve: 10, calendar: calendar))
        XCTAssertEqual(start.todayRemaining, 50 / 7, accuracy: 0.001)
        planner = try JSONDecoder().decode(PacingPlanner.self, from: JSONEncoder().encode(planner))
        let later = try XCTUnwrap(planner.update(remaining: 58, reset: reset, now: now.addingTimeInterval(3600), reserve: 10, calendar: calendar))
        XCTAssertEqual(later.todayRemaining, 50 / 7 - 2, accuracy: 0.001)
        let changed = try XCTUnwrap(planner.update(remaining: 58, reset: reset, now: now.addingTimeInterval(3600), reserve: 58, calendar: calendar))
        XCTAssertEqual(changed.todayRemaining, 0)
        XCTAssertEqual(changed.todayRemainingPercent, 0)
        XCTAssertEqual(changed.dailyPace, 0)
    }

    func testResetExpiryAndReplenishment() throws {
        var planner = PacingPlanner()
        let now = date("2026-11-09T00:00:00Z"), reset = now.addingTimeInterval(3600)
        let lastHour = try XCTUnwrap(planner.update(remaining: 8, reset: reset, now: now, reserve: 0, calendar: calendar))
        XCTAssertEqual(lastHour.todayRemaining, 8)
        XCTAssertEqual(lastHour.dailyPace, 8)
        XCTAssertNil(planner.update(remaining: 8, reset: reset, now: reset, reserve: 0, calendar: calendar))
        let newCycle = try XCTUnwrap(planner.update(remaining: 100, reset: reset.addingTimeInterval(7 * 86_400), now: reset, reserve: 0, calendar: calendar))
        XCTAssertEqual(newCycle.dailyPace, 100 / 7, accuracy: 0.001)
        XCTAssertNil(planner.update(remaining: .nan, reset: reset, now: now, reserve: 0, calendar: calendar))
    }

    func testPartialReplenishmentStartsAFreshProratedBudget() throws {
        var planner = PacingPlanner()
        let now = date("2026-11-09T00:00:00Z"), reset = date("2026-11-13T00:00:00Z")
        _ = planner.update(remaining: 60, reset: reset, now: now, reserve: 0, calendar: calendar)
        _ = planner.update(remaining: 30, reset: reset, now: now.addingTimeInterval(3600), reserve: 0, calendar: calendar)
        planner = try JSONDecoder().decode(PacingPlanner.self, from: JSONEncoder().encode(planner))
        let replenished = try XCTUnwrap(planner.update(remaining: 50, reset: reset, now: now.addingTimeInterval(12 * 3600), reserve: 0, calendar: calendar))
        XCTAssertEqual(replenished.todayRemaining, 50 / 7, accuracy: 0.001)
    }

    func testTimezoneAndClockChangesReanchor() throws {
        var planner = PacingPlanner(), local = calendar
        let now = date("2026-11-09T12:00:00Z"), reset = date("2026-11-13T00:00:00Z")
        _ = planner.update(remaining: 60, reset: reset, now: now, reserve: 0, calendar: calendar)
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let moved = try XCTUnwrap(planner.update(remaining: 60, reset: reset, now: now, reserve: 0, calendar: local))
        XCTAssertEqual(moved.todayRemaining, 60 * 17 / 84, accuracy: 0.001)
        let back = try XCTUnwrap(planner.update(remaining: 60, reset: reset, now: now.addingTimeInterval(-3600), reserve: 0, calendar: local))
        XCTAssertEqual(back.todayRemaining, 60 * 18 / 85, accuracy: 0.001)
    }

    func testDSTUsesActualLengthOfLocalDay() throws {
        var planner = PacingPlanner(), local = calendar
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let now = date("2026-11-01T04:00:00Z"), reset = date("2026-11-05T05:00:00Z")
        let result = try XCTUnwrap(planner.update(remaining: 60, reset: reset, now: now, reserve: 0, calendar: local))
        XCTAssertEqual(result.todayRemaining, 60 * 25 / 97, accuracy: 0.001)
    }
}
