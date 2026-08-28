import XCTest
@testable import SessionLimitTracker

final class ClaudeOAuthParseTests: XCTestCase {

    /// The real /api/oauth/usage shape (utilization on a 0–100 scale).
    func testRealShape() throws {
        let json = #"""
        {"five_hour":{"utilization":19.0,"resets_at":"2026-08-28T17:39:59.568658+00:00"},
         "seven_day":{"utilization":17.0,"resets_at":"2026-08-30T22:59:59.568683+00:00"},
         "nimbus_quill":{"utilization":0.0,"resets_at":null},
         "limits":[{"kind":"session","group":"session","percent":19,"resets_at":"2026-08-28T17:39:59.568658+00:00"},
                   {"kind":"weekly_all","group":"weekly","percent":17,"resets_at":"2026-08-30T22:59:59.568683+00:00"}]}
        """#
        let p = try XCTUnwrap(ClaudeOAuthProvider.parse(Data(json.utf8)))
        XCTAssertEqual(p.session?.percentUsed ?? 0, 0.19, accuracy: 0.001)
        XCTAssertEqual(p.weekly?.percentUsed ?? 0, 0.17, accuracy: 0.001)
        XCTAssertNotNil(p.session?.resetsAt)
        XCTAssertNotNil(p.weekly?.resetsAt)
    }

    /// Falls back to the `limits` array when the top-level windows are absent.
    func testLimitsArrayFallback() throws {
        let json = #"""
        {"limits":[{"kind":"session","group":"session","percent":42,"resets_at":"2026-08-28T17:39:59Z"},
                   {"kind":"weekly_all","group":"weekly","percent":90,"resets_at":"2026-08-30T22:59:59Z"}]}
        """#
        let p = try XCTUnwrap(ClaudeOAuthProvider.parse(Data(json.utf8)))
        XCTAssertEqual(p.session?.percentUsed ?? 0, 0.42, accuracy: 0.001)
        XCTAssertEqual(p.weekly?.percentUsed ?? 0, 0.90, accuracy: 0.001)
    }

    func testFractionalDateParsing() {
        XCTAssertNotNil(ClaudeOAuthProvider.parseDate("2026-08-28T17:39:59.568658+00:00"))
        XCTAssertNotNil(ClaudeOAuthProvider.parseDate("2026-08-28T17:39:59Z"))
    }

    func testUnrecognizedShapeReturnsNil() {
        XCTAssertNil(ClaudeOAuthProvider.parse(Data(#"{"foo":1}"#.utf8)))
    }
}
