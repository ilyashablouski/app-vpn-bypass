import XCTest
@testable import BypassCore

final class DNSResolverFilesTests: XCTestCase {
    private var dir: String!

    override func setUp() {
        dir = NSTemporaryDirectory() + "resolver-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func read(_ name: String) -> String? { try? String(contentsOfFile: "\(dir!)/\(name)", encoding: .utf8) }

    func testCreatesFilePerDomainWithNameserver() {
        XCTAssertTrue(DNSResolverFiles.sync(domains: ["ozon.by"], server: "192.168.7.1", directory: dir))
        XCTAssertEqual(read("ozon.by"), "# managed by VPN Bypass\nnameserver 192.168.7.1\n")
    }

    func testSecondSyncWithSameInputChangesNothing() {
        DNSResolverFiles.sync(domains: ["ozon.by"], server: "192.168.7.1", directory: dir)
        XCTAssertFalse(DNSResolverFiles.sync(domains: ["ozon.by"], server: "192.168.7.1", directory: dir))
    }

    func testServerChangeRewritesAndRemovedDomainDeletesFile() {
        DNSResolverFiles.sync(domains: ["a.com", "b.com"], server: "192.168.7.1", directory: dir)
        XCTAssertTrue(DNSResolverFiles.sync(domains: ["a.com"], server: "10.0.0.2", directory: dir))
        XCTAssertEqual(read("a.com"), "# managed by VPN Bypass\nnameserver 10.0.0.2\n")
        XCTAssertNil(read("b.com"))
    }

    func testForeignFilesAreNeverTouched() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "nameserver 1.1.1.1\n".write(toFile: "\(dir!)/mine.com", atomically: true, encoding: .utf8)
        DNSResolverFiles.sync(domains: ["mine.com"], server: "192.168.7.1", directory: dir)
        XCTAssertEqual(read("mine.com"), "nameserver 1.1.1.1\n")
        DNSResolverFiles.removeAll(directory: dir)
        XCTAssertEqual(read("mine.com"), "nameserver 1.1.1.1\n")
    }

    func testUnsafeNamesAreSkipped() {
        DNSResolverFiles.sync(domains: ["../evil", "a/b.com", "localhost", ""], server: "192.168.7.1", directory: dir)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [], [])
    }

    func testRemoveAllRemovesOnlyOwnedFiles() {
        DNSResolverFiles.sync(domains: ["a.com", "b.com"], server: "192.168.7.1", directory: dir)
        XCTAssertTrue(DNSResolverFiles.removeAll(directory: dir))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [], [])
    }

    func testSettingsWithoutNewKeysKeepDefaults() throws {
        let old = #"{"entries":[],"bypassEnabled":true,"autoResume":false,"interval":45}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: old)
        XCTAssertTrue(s.bypassEnabled)
        XCTAssertFalse(s.autoResume)
        XCTAssertEqual(s.interval, 45)
        XCTAssertTrue(s.resolveViaPhysicalDNS)
        XCTAssertNil(s.dnsServer)
    }
}
