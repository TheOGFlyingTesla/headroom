import XCTest
@testable import HeadroomCore

final class QuotaTests: XCTestCase {
    private func decode(_ json: String) throws -> QuotaResponse {
        try JSONDecoder().decode(QuotaResponse.self, from: Data(json.utf8))
    }

    func testWeeklyPrimaryShape() throws {
        let response = try decode(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1735689600},"secondary":null}}}"#)
        XCTAssertEqual(response.weekly?.remaining, 75)
        XCTAssertEqual(response.weekly?.resetDate?.timeIntervalSince1970, 1735689600)
    }

    func testWeeklySecondaryAndLegacyResponse() throws {
        let response = try decode(#"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300},"secondary":{"usedPercent":20,"windowDurationMins":10080}}}"#)
        XCTAssertEqual(response.weekly?.remaining, 80)
    }

    func testNeverShowsShortWindowAsWeekly() throws {
        XCTAssertNil(try decode(#"{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300}}}"#).weekly)
    }

    func testNeverSubstitutesAnotherBucket() throws {
        XCTAssertNil(try decode(#"{"rateLimits":{"primary":{"usedPercent":50,"windowDurationMins":10080}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":1,"windowDurationMins":10080}}}}"#).weekly)
    }

    func testMissingWindowIsUnknown() throws {
        XCTAssertNil(try decode(#"{"rateLimits":{"primary":null,"secondary":null}}"#).weekly)
        XCTAssertNil(try decode(#"{"rateLimits":{"primary":{"usedPercent":20}}}"#).weekly)
    }

    func testRemainingIsBounded() throws {
        XCTAssertEqual(try decode(#"{"rateLimits":{"primary":{"usedPercent":105,"windowDurationMins":10080}}}"#).weekly?.remaining, 0)
        XCTAssertEqual(try decode(#"{"rateLimits":{"primary":{"usedPercent":-5,"windowDurationMins":10080}}}"#).weekly?.remaining, 100)
    }
    func testCreditsRemainAvailableWhenWeeklyIsExhausted() throws {
        let response = try decode(#"{"rateLimitsByLimitId":{"codex":{"secondary":{"usedPercent":100,"windowDurationMins":10080},"credits":{"hasCredits":true,"unlimited":false,"balance":"1234.50"}}}}"#)
        XCTAssertEqual(response.weekly?.remaining, 0)
        XCTAssertEqual(response.credits?.amount, Decimal(string: "1234.50"))
    }

    func testCreditsDoNotRequireAWeeklyWindow() throws {
        let response = try decode(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":false,"balance":"12.75"}}}"#)
        XCTAssertNil(response.weekly)
        XCTAssertEqual(response.credits?.amount, Decimal(string: "12.75"))
        XCTAssertNotNil(response.credits?.formatted)
    }

    func testCreditsMissingAndInvalidAreUnknown() throws {
        XCTAssertNil(try decode(#"{"rateLimits":{}}"#).credits)
        for balance in ["null", #""bad""#, #""12oops""#, #""-1""#] {
            let response = try decode("{\"rateLimits\":{\"credits\":{\"hasCredits\":true,\"unlimited\":false,\"balance\":\(balance)}}}")
            XCTAssertNil(response.credits?.formatted)
        }
    }

    func testZeroAndUnlimitedCredits() throws {
        XCTAssertEqual(try decode(#"{"rateLimits":{"credits":{"hasCredits":false,"unlimited":false,"balance":"0"}}}"#).credits?.amount, 0)
        XCTAssertEqual(try decode(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":true,"balance":null}}}"#).credits?.formatted, "∞")
    }

    func testNeverSubstitutesAnotherCreditBucket() throws {
        XCTAssertNil(try decode(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":false,"balance":"100"}},"rateLimitsByLimitId":{"other":{"credits":{"hasCredits":true,"unlimited":false,"balance":"200"}}}}"#).credits)
    }

}
