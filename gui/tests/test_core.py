import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import core  # noqa: E402

NETSTAT_VPN = """Destination Gateway Flags Netif Expire
default 10.8.0.1 UGScg utun4
default 192.168.1.1 UGScIg en0
"""
NETSTAT_SPLIT = "0/1 10.8.0.1 UGSc utun4\n128.0/1 10.8.0.1 UGSc utun4\ndefault 192.168.1.1 UGScg en0\n"
NETSTAT_OFF = "default 192.168.1.1 UGScg en0\n10.8.0.0/24 link#18 UCS utun4\n"


class CoreTests(unittest.TestCase):
    def test_vpn_detection(self):
        self.assertTrue(core.parse_vpn_active(NETSTAT_VPN))
        self.assertTrue(core.parse_vpn_active(NETSTAT_SPLIT))
        self.assertFalse(core.parse_vpn_active(NETSTAT_OFF))

    def test_config_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "c.conf"
            entries = [("host", "ya.ru"), ("app", "Telegram"), ("host", "10.0.0.0/8")]
            core.save_entries(entries, p)
            self.assertEqual(core.load_entries(p), entries)

    def test_load_ignores_comments(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "c.conf"
            p.write_text("# x\nya.ru # c\n\napp: Slack\n")
            self.assertEqual(core.load_entries(p), [("host", "ya.ru"), ("app", "Slack")])

    def test_normalize_and_validate(self):
        self.assertEqual(core.normalize_host("https://Ya.ru/path?q=1"), "ya.ru")
        self.assertEqual(core.normalize_host("10.0.0.0/8"), "10.0.0.0/8")
        self.assertTrue(core.valid_host("ya.ru"))
        self.assertTrue(core.valid_host("*.sber.ru"))
        self.assertTrue(core.valid_host("1.2.3.4"))
        self.assertFalse(core.valid_host("not a host"))

    def test_add_entry_no_duplicates(self):
        e = []
        self.assertTrue(core.add_entry(e, "host", "ya.ru"))
        self.assertFalse(core.add_entry(e, "host", "ya.ru"))

    def test_app_process_name_fallback(self):
        self.assertEqual(core.app_process_name("/nonexistent/Foo.app"), "Foo")


if __name__ == "__main__":
    unittest.main()
