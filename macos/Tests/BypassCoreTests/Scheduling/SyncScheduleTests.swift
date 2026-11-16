import XCTest
@testable import BypassCore

final class SyncScheduleTests: XCTestCase {
    func testBaseIntervalWhileChanging() {
        XCTAssertEqual(SyncSchedule.delay(base: 30, unchanged: 0, hasApps: false), 30)
        XCTAssertEqual(SyncSchedule.delay(base: 30, unchanged: 2, hasApps: true), 30)
    }

    func testBacksOffWhenNothingChanges() {
        XCTAssertEqual(SyncSchedule.delay(base: 30, unchanged: 3, hasApps: false), 60)
        XCTAssertEqual(SyncSchedule.delay(base: 30, unchanged: 6, hasApps: false), 120)
    }

    func testAppsBackOffLessSoNewConnectionsAreCoveredSooner() {
        XCTAssertEqual(SyncSchedule.delay(base: 30, unchanged: 10, hasApps: true), 60)
    }

    func testCappedButNeverBelowBase() {
        XCTAssertEqual(SyncSchedule.delay(base: 100, unchanged: 10, hasApps: false), 300)
        XCTAssertEqual(SyncSchedule.delay(base: 400, unchanged: 10, hasApps: false), 400)
    }
}
