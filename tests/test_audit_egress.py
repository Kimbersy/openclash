import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "audit_egress.py"
spec = importlib.util.spec_from_file_location("audit_egress", MODULE)
egress = importlib.util.module_from_spec(spec)
spec.loader.exec_module(egress)


def with_subscription_snapshot(inv: dict) -> dict:
    return inv | {
        "subscription_snapshot": {"sha256": "b" * 64, "byte_count": 99},
        "source_node_count": max(1, len(inv.get("nodes", []))),
    }


class EgressAuditTests(unittest.TestCase):
    def setUp(self):
        self.tw = [
            {"source": "ipinfo", "ip": "203.0.113.8", "country": "TW"},
            {"source": "ipapi", "ip": "203.0.113.8", "country": "TW"},
        ]
        self.hk = [
            {"source": "ipinfo", "ip": "203.0.113.9", "country": "HK"},
            {"source": "ipapi", "ip": "203.0.113.9", "country": "HK"},
        ]

    def test_label_parser_and_ambiguity(self):
        self.assertEqual(egress.advertised_country("🇹🇼 台湾 01"), "TW")
        self.assertEqual(egress.advertised_country("日本東京 02"), "JP")
        self.assertEqual(egress.advertised_country("Singapore 03"), "SG")
        self.assertIsNone(egress.advertised_country("台湾 香港 合并"))
        self.assertIsNone(egress.advertised_country("IPLC 专线"))

    def test_classification_matches_and_mismatch(self):
        self.assertEqual(egress.classify("台湾01", self.tw, [])["status"], "match")
        rec = egress.classify("台湾02", self.hk, [])
        self.assertEqual(rec["status"], "mismatch")
        self.assertEqual(rec["observed_country"], "HK")
        self.assertEqual(rec["claimed_country"], "TW")

    def test_real_hk_exit_independent_from_taiwan_label_and_service(self):
        mislabeled = egress.classify("台湾 05", self.hk, [])
        self.assertEqual(mislabeled["claimed_country"], "TW")
        self.assertEqual(mislabeled["observed_country"], "HK")
        self.assertEqual(mislabeled["status"], "mismatch")
        self.assertTrue(mislabeled["egress_verified"])
        self.assertEqual(mislabeled["service_availability"], {})
        unknown_label = egress.classify("IPLC 独立节点", self.hk, [])
        self.assertIsNone(unknown_label["claimed_country"])
        self.assertEqual(unknown_label["observed_country"], "HK")
        self.assertTrue(unknown_label["egress_verified"])
        self.assertEqual(unknown_label["status"], "unknown")

    def test_egress_country_filters_include_mismatches_and_unlabeled_nodes(self):
        inventory = {"schema_version": 1, "nodes": [
            {"name": "台湾05", "proxy_url": "http://127.0.0.1:7181"},
            {"name": "香港03", "proxy_url": "http://127.0.0.1:7182"},
            {"name": "IPLC", "proxy_url": "http://127.0.0.1:7183"},
        ]}
        with patch.object(egress, "probe", side_effect=[
            (self.hk, []), (self.hk, []), (self.tw, [])
        ]):
            report = egress.audit(with_subscription_snapshot(inventory))
        self.assertEqual([x["observed_country"] for x in report["nodes"]], ["HK", "HK", "TW"])
        self.assertTrue(re.search(report["observed_exit_name_filters"]["HK"], "台湾05"))
        self.assertTrue(re.search(report["observed_exit_name_filters"]["HK"], "香港03"))
        self.assertTrue(re.search(report["observed_exit_name_filters"]["TW"], "IPLC"))
        self.assertFalse(re.search(report["verified_name_filters"]["TW"], "台湾05"))
        self.assertEqual(report["nodes"][0]["service_availability"], {})

    def test_unknown_and_inconsistent(self):
        self.assertEqual(egress.classify("台湾01", self.tw[:1], [])["status"], "unknown")
        self.assertEqual(egress.classify("IPLC", self.tw, [])["status"], "unknown")
        self.assertTrue(egress.classify("IPLC", self.tw, [])["egress_verified"])
        self.assertIsNone(egress.classify("台湾01", self.tw[:1], [])["observed_country"])
        diff_ip = [self.tw[0], {**self.tw[1], "ip": "203.0.113.7"}]
        self.assertEqual(egress.classify("台湾01", diff_ip, [])["status"], "inconsistent")
        diff_country = [self.tw[0], {**self.tw[1], "country": "US"}]
        self.assertEqual(egress.classify("台湾01", diff_country, [])["status"], "inconsistent")

    def test_report_pins_current_subscription_snapshot(self):
        inv=with_subscription_snapshot({"schema_version": 1, "nodes": [
            {"name": "日本01", "proxy_url": "http://127.0.0.1:7191"},
        ]})
        with patch.object(egress, "probe", return_value=(self.tw, [])):
            out=egress.audit(inv)
        self.assertEqual(out["subscription_snapshot"], inv["subscription_snapshot"])
        self.assertEqual(out["source_node_count"], 1)
        with self.assertRaises(ValueError):
            egress.audit({"schema_version": 1, "nodes": inv["nodes"]})

    def test_loopback_only_no_credentials(self):
        for valid in ("http://127.0.0.1:8081", "http://localhost:8000", "http://[::1]:8999"):
            self.assertEqual(egress.validate_local_proxy(valid), valid)
        bad = ("socks5://127.0.0.1:1234", "http://8.8.8.8:80",
               "http://127.0.0.1.attacker.com:80", "http://user:pass@127.0.0.1:8000",
               "http://127.0.0.1:8000/path", "http://127.0.0.1",
               "http://127.0.0.1:99999")
        for item in bad:
            with self.subTest(item=item), self.assertRaises(ValueError):
                egress.validate_local_proxy(item)

    def test_exact_filter_no_false_matches(self):
        pattern = egress.exact_name_regex(["台湾(01)", "台北 02"])
        self.assertTrue(re.search(pattern, "台湾(01)"))
        self.assertTrue(re.search(pattern, "台北 02"))
        self.assertFalse(re.search(pattern, "台湾(02)"))
        self.assertFalse(re.search(pattern, "台北 021"))
        self.assertFalse(re.search(egress.exact_name_regex([]), "台湾01"))

    def test_reject_duplicate_names_or_ports(self):
        for nodes in (
            [{"name": "台湾01", "proxy_url": "http://127.0.0.1:7011"},
             {"name": "台湾01", "proxy_url": "http://127.0.0.1:7012"}],
            [{"name": "台湾01", "proxy_url": "http://127.0.0.1:7011"},
             {"name": "台湾02", "proxy_url": "http://127.0.0.1:7011"}],
        ):
            with self.subTest(nodes=nodes), self.assertRaises(ValueError):
                with patch.object(egress, "probe", return_value=(self.tw, [])):
                    egress.audit(with_subscription_snapshot({"schema_version": 1, "nodes": nodes}))

    def test_mock_end_to_end_report_and_exact_filter(self):
        inventory = {"schema_version": 1, "nodes": [
            {"name": "台湾01", "proxy_url": "http://127.0.0.1:7101"},
            {"name": "台湾02", "proxy_url": "http://127.0.0.1:7102"},
            {"name": "未标记", "proxy_url": "http://127.0.0.1:7103"},
        ]}
        with patch.object(egress, "probe", side_effect=[(self.tw, []), (self.hk, []), ([], ["ipinfo:TimeoutError"])]):
            out = egress.audit(with_subscription_snapshot(inventory))
        self.assertEqual([n["status"] for n in out["nodes"]], ["match", "mismatch", "unknown"])
        self.assertTrue(re.search(out["verified_name_filters"]["TW"], "台湾01"))
        self.assertFalse(re.search(out["verified_name_filters"]["TW"], "台湾02"))
        self.assertFalse(re.search(out["verified_name_filters"]["TW"], "未标记"))
        self.assertIn("generated_at", out)

    def test_json_report_file_permissions(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "private" / "report.json"
            egress.secure_write_json(p, {"schema_version": 1, "nodes": []})
            self.assertEqual(json.loads(p.read_text())["schema_version"], 1)
            if hasattr(p.stat(), "st_mode"):
                self.assertEqual(p.stat().st_mode & 0o777, 0o600)

    def test_malformed_inventory_rejected(self):
        with self.assertRaises(ValueError):
            egress.audit({"schema_version": 0, "nodes": []})
        with self.assertRaises(ValueError):
            egress.audit(with_subscription_snapshot({"schema_version": 1, "nodes": [{}]}))
        with self.assertRaises(ValueError):
            egress.audit(with_subscription_snapshot({"schema_version": 1, "nodes": [{"name": "台湾\n01", "proxy_url": "http://127.0.0.1:80"}]}))


if __name__ == "__main__":
    unittest.main()
