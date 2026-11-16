import XCTest
import Darwin
@testable import BypassCore

private final class MockBackend: RouteBackend {
    var added: [IPv4Target] = []
    var deleted: [IPv4Target] = []
    var addResult: [IPv4Target: Int32] = [:]

    func add(_ target: IPv4Target, gateway: UInt32) -> Int32 {
        let e = addResult[target] ?? 0
        if e == 0 { added.append(target) }
        return e
    }
    func delete(_ target: IPv4Target) -> Int32 { deleted.append(target); return 0 }
}

final class RouteManagerTests: XCTestCase {
    private func t(_ s: String) -> IPv4Target { IPv4Target(s)! }
    private let gw: UInt32 = 0xC0A8_0101

    func testDiffAddsAndRemoves() {
        let d = RouteDiff.compute(desired: [t("1.1.1.1"), t("2.2.2.2")], current: [t("2.2.2.2"), t("3.3.3.3")])
        XCTAssertEqual(d.add, [t("1.1.1.1")])
        XCTAssertEqual(d.remove, [t("3.3.3.3")])
    }

    func testSyncIsIdempotentAndRemovesStale() {
        let b = MockBackend()
        let m = RouteManager(backend: b)
        m.sync(desired: [t("1.1.1.1"), t("2.2.2.2")], gateway: gw)
        m.sync(desired: [t("1.1.1.1")], gateway: gw)
        XCTAssertEqual(b.added.count, 2)
        XCTAssertEqual(b.deleted, [t("2.2.2.2")])
        XCTAssertEqual(m.owned, [t("1.1.1.1")])
    }

    func testGatewayChangeReinstallsRoutes() {
        let b = MockBackend()
        let m = RouteManager(backend: b)
        m.sync(desired: [t("1.1.1.1")], gateway: gw)
        m.sync(desired: [t("1.1.1.1")], gateway: gw + 1)
        XCTAssertEqual(b.added.count, 2)
        XCTAssertEqual(b.deleted, [t("1.1.1.1")])
    }

    func testExistingForeignRouteIsNotOwned() {
        let b = MockBackend()
        b.addResult[t("1.1.1.1")] = EEXIST
        let m = RouteManager(backend: b)
        XCTAssertEqual(m.sync(desired: [t("1.1.1.1")], gateway: gw), 0)
        XCTAssertTrue(m.owned.isEmpty)
    }

    func testFailuresCountedAndGatewayItselfSkipped() {
        let b = MockBackend()
        b.addResult[t("9.9.9.9")] = ENETUNREACH
        let m = RouteManager(backend: b)
        let failures = m.sync(desired: [t("9.9.9.9"), IPv4Target(address: gw)], gateway: gw)
        XCTAssertEqual(failures, 1)
        XCTAssertTrue(b.added.isEmpty)
    }

    func testRemoveAllClearsOwned() {
        let b = MockBackend()
        let m = RouteManager(backend: b)
        m.sync(desired: [t("1.1.1.1"), t("10.0.0.0/8")], gateway: gw)
        m.removeAll()
        XCTAssertTrue(m.owned.isEmpty)
        XCTAssertEqual(Set(b.deleted), [t("1.1.1.1"), t("10.0.0.0/8")])
    }

    func testRouteMessageLayout() {
        let host = RouteMessage.add(t("8.8.4.4"), gateway: gw, seq: 7)
        XCTAssertEqual(host.count, RouteTable.headerSize + 32)
        XCTAssertEqual(Int(host[0]) | Int(host[1]) << 8, host.count)
        XCTAssertEqual(host[2], 5)
        XCTAssertEqual(host[3], 1) // RTM_ADD
        XCTAssertEqual(Array(host[RouteTable.headerSize + 4..<RouteTable.headerSize + 8]), [8, 8, 4, 4])

        let net = RouteMessage.delete(t("10.0.0.0/8"), seq: 8)
        XCTAssertEqual(net[3], 2) // RTM_DELETE
        XCTAssertEqual(net.count, RouteTable.headerSize + 32) // dst + netmask
        XCTAssertEqual(Array(net[RouteTable.headerSize + 20..<RouteTable.headerSize + 24]), [255, 0, 0, 0])
    }
}
