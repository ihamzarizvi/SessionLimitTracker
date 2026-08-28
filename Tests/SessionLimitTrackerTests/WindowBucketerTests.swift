import XCTest
@testable import SessionLimitTracker

final class WindowBucketerTests: XCTestCase {

    private func ev(_ offsetSeconds: TimeInterval, _ tokens: Int, from base: Date, rateLimit: Bool = false) -> UsageEvent {
        UsageEvent(timestamp: base.addingTimeInterval(offsetSeconds), tokens: tokens,
                   id: UUID().uuidString, isRateLimit: rateLimit)
    }

    func testSessionWindowSumsCurrentBlock() {
        let now = Date()
        let start = now.addingTimeInterval(-3600) // 1h ago, still inside 5h window
        var b = WindowBucketer()
        b.calibration = Calibration(sessionTokenCapacity: 1000, weeklyTokenCapacity: 100_000)
        let events = [
            ev(0, 300, from: start),
            ev(600, 200, from: start)
        ]
        let w = b.sessionWindow(events: events, now: now)
        XCTAssertEqual(w.percentUsed, 0.5, accuracy: 0.0001)
        XCTAssertNotNil(w.resetsAt)
        XCTAssertEqual(w.resetsAt!.timeIntervalSince1970,
                       start.addingTimeInterval(5 * 3600).timeIntervalSince1970, accuracy: 1)
    }

    func testSessionWindowResetsAfterFiveHours() {
        let now = Date()
        let start = now.addingTimeInterval(-6 * 3600) // older than 5h
        var b = WindowBucketer()
        b.calibration = Calibration(sessionTokenCapacity: 1000, weeklyTokenCapacity: 100_000)
        let w = b.sessionWindow(events: [ev(0, 900, from: start)], now: now)
        XCTAssertEqual(w.percentUsed, 0)
        XCTAssertNil(w.resetsAt)
    }

    func testNewBlockStartsAfterGap() {
        let now = Date()
        let old = now.addingTimeInterval(-8 * 3600)
        let recent = now.addingTimeInterval(-1800) // 30 min ago
        var b = WindowBucketer()
        b.calibration = Calibration(sessionTokenCapacity: 1000, weeklyTokenCapacity: 100_000)
        let events = [
            ev(0, 999, from: old),      // old block, should be ignored
            ev(0, 250, from: recent)    // current block
        ].sorted { $0.timestamp < $1.timestamp }
        let w = b.sessionWindow(events: events, now: now)
        XCTAssertEqual(w.percentUsed, 0.25, accuracy: 0.0001)
    }

    func testCalibrationFromRateLimit() {
        let now = Date()
        let start = now.addingTimeInterval(-1800)
        let b = WindowBucketer()
        let events = [
            ev(0, 400, from: start),
            ev(60, 600, from: start, rateLimit: true)
        ]
        let cal = b.calibrated(from: events, now: now)
        XCTAssertEqual(cal.sessionTokenCapacity, 1000, accuracy: 0.001)
    }
}
