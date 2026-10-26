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
}
