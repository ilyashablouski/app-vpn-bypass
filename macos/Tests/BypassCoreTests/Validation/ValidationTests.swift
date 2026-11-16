import XCTest
@testable import BypassCore

final class ValidationTests: XCTestCase {
    func testNormalizeHost() {
        XCTAssertEqual(Validation.normalizeHost("  HTTPS://Example.COM/path?q=1 "), "example.com")
        XCTAssertEqual(Validation.normalizeHost("example.com:8443"), "example.com")
        XCTAssertEqual(Validation.normalizeHost("10.0.0.0/8"), "10.0.0.0/8")
    }

    func testValidHost() {
        XCTAssertTrue(Validation.isValidHost("example.com"))
        XCTAssertTrue(Validation.isValidHost("*.example.com"))
        XCTAssertTrue(Validation.isValidHost("1.2.3.4"))
        XCTAssertTrue(Validation.isValidHost("10.0.0.0/8"))
        XCTAssertFalse(Validation.isValidHost("999.1.1.1"))
        XCTAssertFalse(Validation.isValidHost("1.2.3.4/33"))
        XCTAssertFalse(Validation.isValidHost("localhost"))
        XCTAssertFalse(Validation.isValidHost("bad host.com"))
    }

    func testStripWildcard() {
        XCTAssertEqual(Validation.stripWildcard("*.example.com"), "example.com")
        XCTAssertEqual(Validation.stripWildcard("example.com"), "example.com")
    }

    func testIPv4TargetParsingAndMasking() {
        XCTAssertEqual(IPv4Target("10.1.2.3/8")?.description, "10.0.0.0/8")
        XCTAssertEqual(IPv4Target("1.2.3.4")?.description, "1.2.3.4")
        XCTAssertNil(IPv4Target("1.2.3"))
        XCTAssertNil(IPv4Target("1.2.3.256"))
    }

    func testAppProcessNameFallsBackToBundleName() {
        let url = URL(fileURLWithPath: "/nonexistent/Some App.app")
        XCTAssertEqual(Validation.appProcessName(appURL: url), "Some App")
    }

    func testAppConnectionsMatching() {
        let byPath = Entry(kind: .app, value: "Chrome", path: "/Applications/Google Chrome.app")
        XCTAssertTrue(AppConnections.matches(
            entry: byPath, processPath: "/Applications/Google Chrome.app/Contents/Frameworks/Helper"))
        XCTAssertFalse(AppConnections.matches(entry: byPath, processPath: "/usr/bin/other"))
        let byName = Entry(kind: .app, value: "curl")
        XCTAssertTrue(AppConnections.matches(entry: byName, processPath: "/usr/bin/curl"))
    }
}
