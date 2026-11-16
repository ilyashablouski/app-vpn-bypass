import XCTest
@testable import BypassCore

final class ConfigTests: XCTestCase {
    func testLegacyParseSkipsCommentsAndInvalid() {
        let text = """
        # комментарий
        example.com   # хвост
        https://Foo.org/x
        1.2.3.4
        not a host
        app: Telegram
        example.com
        """
        let entries = LegacyConfig.parse(text)
        XCTAssertEqual(entries, [
            Entry(kind: .host, value: "example.com", note: "хвост"),
            Entry(kind: .host, value: "foo.org"),
            Entry(kind: .host, value: "1.2.3.4"),
            Entry(kind: .app, value: "Telegram"),
        ])
    }

    func testSettingsRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        var s = Settings()
        s.entries = [Entry(kind: .app, value: "Safari", path: "/Applications/Safari.app")]
        s.bypassEnabled = true
        s.gatewayOverride = "192.168.0.1"
        try SettingsStore.save(s, to: url)
        XCTAssertEqual(SettingsStore.load(from: url), s)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testLoadMissingFileGivesDefaults() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).json")
        XCTAssertEqual(SettingsStore.load(from: url), Settings())
    }

    func testNoteIsTrimmedAndEmptyBecomesNil() {
        XCTAssertEqual(Entry(kind: .host, value: "a.com", note: "  мой VPS  ").note, "мой VPS")
        XCTAssertNil(Entry(kind: .host, value: "a.com", note: "   ").note)
        XCTAssertEqual(Entry.cleanNote(String(repeating: "x", count: 500))?.count, 200)
    }

    func testNoteRoundTripAndOldConfigWithoutNote() throws {
        let entry = Entry(kind: .host, value: "94.198.217.159", note: "ssh")
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(Entry.self, from: data), entry)

        // Файл конфигурации старого формата (без поля note) читается без ошибок.
        let old = #"{"kind":"host","value":"example.com"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Entry.self, from: old)
        XCTAssertEqual(decoded.value, "example.com")
        XCTAssertNil(decoded.note)
    }
}
