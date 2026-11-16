import XCTest
@testable import BypassCore

final class RouteTableTests: XCTestCase {
    // MARK: Построение синтетического дампа

    private func sockaddr(len: Int, family: UInt8 = 2, addr: [UInt8]) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: max(len, 4))
        b[0] = UInt8(len); b[1] = family
        for (i, v) in addr.enumerated() where 4 + i < b.count { b[4 + i] = v }
        while b.count % 4 != 0 { b.append(0) }
        return b
    }

    private func message(dst: [UInt8], gw: [UInt8]?, mask: [UInt8]?, maskLen: Int = 16,
                         flags: Int32, index: UInt16) -> [UInt8] {
        var body = sockaddr(len: 16, addr: dst)
        var addrs: UInt32 = 1
        if let gw { body += sockaddr(len: 16, addr: gw); addrs |= 2 }
        if let mask { body += sockaddr(len: maskLen, family: 0, addr: mask); addrs |= 4 }
        var m = [UInt8](repeating: 0, count: RouteTable.headerSize)
        let total = UInt16(m.count + body.count)
        m[0] = UInt8(total & 255); m[1] = UInt8(total >> 8)
        m[2] = 5; m[3] = 4
        m[4] = UInt8(index & 255); m[5] = UInt8(index >> 8)
        withUnsafeBytes(of: UInt32(bitPattern: flags).littleEndian) { for i in 0..<4 { m[8 + i] = $0[i] } }
        withUnsafeBytes(of: addrs.littleEndian) { for i in 0..<4 { m[12 + i] = $0[i] } }
        return m + body
    }

    private let names: [UInt16: String] = [4: "en0", 17: "utun4"]
    private func parse(_ b: [UInt8]) -> [RouteInfo] { RouteTable.parse(b) { self.names[$0] ?? "" } }

    // MARK: Тесты

    func testParseDefaultAndHostRoutes() {
        let buf = message(dst: [0, 0, 0, 0], gw: [192, 168, 1, 1], mask: [], maskLen: 0, flags: 0x3, index: 4)
            + message(dst: [8, 8, 8, 8], gw: [192, 168, 1, 1], mask: nil, flags: 0x807, index: 4)
        let routes = parse(buf)
        XCTAssertEqual(routes.count, 2)
        XCTAssertTrue(routes[0].isDefault)
        XCTAssertEqual(routes[0].gateway, 0xC0A8_0101)
        XCTAssertEqual(routes[0].interface, "en0")
        XCTAssertEqual(routes[1].destination, 0x0808_0808)
        XCTAssertEqual(routes[1].mask, UInt32.max)
    }

    func testTruncatedNetmask() {
        // 128.0.0.0/1: netmask 128.0.0.0, sa_len = 5
        let buf = message(dst: [128, 0, 0, 0], gw: [10, 0, 0, 1], mask: [128], maskLen: 5, flags: 0x3, index: 17)
        let r = parse(buf)
        XCTAssertEqual(r.first?.mask, 0x8000_0000)
        XCTAssertEqual(r.first?.destination, 0x8000_0000)
    }

    func testVPNDetectedByHalfRoutesOnUtun() {
        let buf = message(dst: [0, 0, 0, 0], gw: [192, 168, 1, 1], mask: [], maskLen: 0, flags: 0x3, index: 4)
            + message(dst: [0, 0, 0, 0], gw: [10, 8, 0, 1], mask: [128], maskLen: 5, flags: 0x3, index: 17)
        XCTAssertTrue(NetworkState.isVPNActive(parse(buf)))
    }

    func testNoVPNWhenOnlyPhysicalDefault() {
        let buf = message(dst: [0, 0, 0, 0], gw: [192, 168, 1, 1], mask: [], maskLen: 0, flags: 0x3, index: 4)
        XCTAssertFalse(NetworkState.isVPNActive(parse(buf)))
    }

    func testScopedUtunDefaultIsIgnored() {
        let buf = message(dst: [0, 0, 0, 0], gw: [10, 8, 0, 1], mask: [], maskLen: 0,
                          flags: 0x3 | 0x1000000, index: 17)
        XCTAssertFalse(NetworkState.isVPNActive(parse(buf)))
    }

    func testPhysicalGatewayPrefersEthernetEvenWhenScoped() {
        let buf = message(dst: [0, 0, 0, 0], gw: [10, 8, 0, 1], mask: [], maskLen: 0, flags: 0x3, index: 17)
            + message(dst: [0, 0, 0, 0], gw: [192, 168, 1, 1], mask: [], maskLen: 0,
                      flags: 0x3 | 0x1000000, index: 4)
        let gw = NetworkState.physicalGateway(parse(buf))
        XCTAssertEqual(gw?.gateway, 0xC0A8_0101)
        XCTAssertEqual(gw?.interface, "en0")
    }

    func testParseGarbageDoesNotCrash() {
        XCTAssertTrue(parse([1, 2, 3]).isEmpty)
        var bad = message(dst: [1, 1, 1, 1], gw: nil, mask: nil, flags: 0, index: 4)
        bad[0] = 0xFF; bad[1] = 0xFF // msglen больше буфера
        XCTAssertTrue(parse(bad).isEmpty)
    }
}
