import XCTest
@testable import BypassCore

final class DNSClientTests: XCTestCase {
    /// Кодирует имя в формате DNS (метки с длиной).
    private func encode(_ name: String) -> [UInt8] {
        var out = [UInt8]()
        for label in name.split(separator: ".") {
            out.append(UInt8(label.utf8.count))
            out.append(contentsOf: Array(label.utf8))
        }
        out.append(0)
        return out
    }

    private func word(_ v: Int) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 255)] }

    private func add(_ packet: inout [UInt8], _ parts: [UInt8]...) {
        for part in parts { packet.append(contentsOf: part) }
    }

    /// Ответ как у роутера: ir.ozone.ru -> mmedia.ozone.ru -> edge-mmedia-lb.ozone.ru -> два адреса (имена сжаты).
    private func sampleResponse(id: Int = 7) -> [UInt8] {
        var p = [UInt8]()
        add(&p, word(id), [0x81, 0x80], word(1), word(4), word(0), word(0))
        let nameOffset = p.count
        add(&p, encode("ir.ozone.ru"), word(1), word(1))

        // CNAME ir.ozone.ru -> mmedia.ozone.ru
        let target1 = encode("mmedia.ozone.ru")
        add(&p, [0xC0, UInt8(nameOffset)], word(5), word(1), [0, 0, 0, 60], word(target1.count))
        let target1Offset = p.count
        add(&p, target1)

        // CNAME mmedia.ozone.ru -> edge-mmedia-lb + ссылка на хвост ".ozone.ru" внутри первой цели (после метки "mmedia")
        var target2 = [UInt8(14)]
        target2.append(contentsOf: Array("edge-mmedia-lb".utf8))
        target2.append(contentsOf: [0xC0, UInt8(target1Offset + 7)])
        add(&p, [0xC0, UInt8(target1Offset)], word(5), word(1), [0, 0, 0, 60], word(target2.count))
        let target2Offset = p.count
        add(&p, target2)

        // Два A-адреса у edge-mmedia-lb.ozone.ru
        let addresses: [[UInt8]] = [[185, 73, 193, 119], [185, 73, 195, 116]]
        for a in addresses {
            add(&p, [0xC0, UInt8(target2Offset)], word(1), word(1), [0, 0, 0, 60], word(4), a)
        }
        return p
    }

    func testParsesCNAMEChainAndAddresses() {
        let answer = DNSClient.parse(sampleResponse(), expectedID: 7)
        XCTAssertEqual(answer?.cnames ?? [], ["mmedia.ozone.ru", "edge-mmedia-lb.ozone.ru"])
        XCTAssertEqual(answer?.addresses.map(\.description) ?? [], ["185.73.193.119", "185.73.195.116"])
    }

    func testRejectsWrongIDAndGarbage() {
        XCTAssertNil(DNSClient.parse(sampleResponse(), expectedID: 8))
        XCTAssertNil(DNSClient.parse([1, 2, 3]))
        var truncated = sampleResponse()
        truncated.removeLast(10)
        XCTAssertNil(DNSClient.parse(truncated, expectedID: 7))
    }

    func testPointerLoopDoesNotHang() {
        var p = [UInt8]()
        add(&p, word(1), [0x81, 0x80], word(1), word(0), word(0), word(0))
        add(&p, [0xC0, 12], word(1), word(1)) // имя указывает само на себя
        XCTAssertNil(DNSClient.parse(p))
    }

    func testBuildQueryLayout() {
        let q = DNSClient.buildQuery(name: "ozon.by", id: 0x1234)
        XCTAssertEqual(Array(q[0..<4]), [0x12, 0x34, 0x01, 0x00])
        var expectedTail = encode("ozon.by")
        expectedTail.append(contentsOf: [0, 1, 0, 1])
        XCTAssertEqual(Array(q[12...]), expectedTail)
    }
}
