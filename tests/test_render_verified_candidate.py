import importlib.util
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "scripts" / "render_verified_candidate.py"
spec = importlib.util.spec_from_file_location("render_verified_candidate", MODULE)
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


def record(name="台湾 01", status="match", cc="TW", actual=None, claimed=None):
    observed = actual or cc
    label = claimed if claimed is not None else cc
    return {
        "name": name, "status": status, "claimed_country": label,
        "observed_country": observed, "observed_ips": ["203.0.113.8"],
        "evidence_sources": ["ipinfo", "ipapi"], "egress_verified": True,
        "service_availability": {},
    }

def report(nodes, stamp=None):
    return {
        "schema_version": 1,
        "generated_at": (stamp or datetime.now(timezone.utc)).isoformat(),
        "nodes": nodes,
        "subscription_snapshot": {"sha256": "a" * 64, "byte_count": 42},
        "source_node_count": max(1, len(nodes)),
    }


class VerifiedCandidateTests(unittest.TestCase):
    def test_observed_exit_not_label_is_authoritative(self):
        names = candidate.verified_names(report([
            record("台湾 01"),
            record("台湾名但香港出口", "mismatch", "TW", actual="HK"),
            record("香港 ChatGPT OK", "match", "HK"),
            record("加拿大出口", "unknown", "CA", claimed=None) | {"claimed_country": None},
            record("美国 01", "match", "US"),
        ]))
        self.assertEqual(names["TW"], ["台湾 01"])
        self.assertEqual(names["HK"], ["台湾名但香港出口", "香港 ChatGPT OK"])
        self.assertEqual(names["CA"], ["加拿大出口"])
        self.assertEqual(names["US"], ["美国 01"])
        self.assertNotIn("香港 ChatGPT OK", names["TW"])

    def test_report_requires_subscription_identity_even_if_fresh(self):
        rec = report([record()])
        for broken in [
            {k:v for k,v in rec.items() if k != "subscription_snapshot"},
            rec | {"subscription_snapshot": {"sha256": "not-a-real-hash", "byte_count": 42}},
            rec | {"source_node_count": 0},
        ]:
            with self.subTest(fields=tuple(sorted(broken))):
                with self.assertRaises(ValueError):
                    candidate.verified_names(broken)

    def test_reject_expired_future_and_naive(self):
        now = datetime.now(timezone.utc)
        for stamp in (now - timedelta(hours=9), now + timedelta(minutes=6),
                      datetime.now().replace(tzinfo=None)):
            with self.subTest(stamp=stamp), self.assertRaises(ValueError):
                candidate.verified_names(report([record()], stamp), now=now)

    def test_reject_fake_match_evidence(self):
        for changed in [
            {"evidence_sources": ["ipinfo"]},
            {"observed_country": "HK"},  # still marked match with TW label
            {"observed_ips": ["203.0.113.8", "203.0.113.9"]},
            {"status": "inconsistent"},
            {"egress_verified": True, "observed_country": "unknown"},
        ]:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                candidate.verified_names(report([record() | changed]))

    def test_unverified_exit_is_never_admitted(self):
        names = candidate.verified_names(report([
            record("台湾 01"),
            record("香港 02", "unknown", "HK") | {"egress_verified": False},
        ]))
        self.assertEqual(names, {"TW": ["台湾 01"]})

    def test_reject_unsafe_names(self):
        for name in ("台湾,01", "台湾" + chr(96) + "01", "台湾\\01", "台湾\n01"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                candidate.verified_names(report([record(name)]))

    def test_anchored_filter_survives_converter_cleanup(self):
        p = candidate.literal_filter(["台湾 01", "台湾(02)"])
        self.assertTrue(re.search(p, "台湾 01"))
        self.assertTrue(re.search(p, "台湾(02)"))
        self.assertFalse(re.search(p, "台湾 012"))
        self.assertFalse(re.search(p, "测试台湾 01"))

    def test_all_observed_exit_countries_include_hk_no_auto_fallback(self):
        src = ("ruleset=🤖 AI,example\ncustom_proxy_group=🤖 AI" + chr(96) +
               "select" + chr(96) + "[]🇸🇬新加坡" + chr(96) + "[]🇹🇼台湾\n" +
               "custom_proxy_group=🏰 Disney+" + chr(96) + "select" + chr(96) + "[]🇸🇬新加坡\n")
        ini = candidate.build_candidate_ini(src, {
            "TW": ["台湾 01"], "HK": ["香港 ChatGPT OK", "台湾名香港出口"],
            "CA": ["未标注加拿大"], "US": ["美国 01"],
        })
        self.assertIn("[]🇸🇬新加坡", ini)
        self.assertIn("[]🇹🇼台湾", ini)
        for cc in ("TW", "HK", "CA", "US"):
            self.assertIn("[]"+candidate.exit_group(cc), ini)
            self.assertIn("custom_proxy_group="+candidate.exit_group(cc), ini)
        self.assertIn("香港 ChatGPT OK", ini)
        self.assertIn(candidate.literal_filter(["香港 ChatGPT OK", "台湾名香港出口"]), ini)
        self.assertIn("custom_proxy_group=🏰 Disney+", ini)
        self.assertNotIn("🛡️AI 稳态🇹🇼台湾", ini)
        self.assertNotIn("`fallback`", "\n".join(line for line in ini.splitlines() if line.startswith("custom_proxy_group=🧭出口")))
        self.assertIn("PLATFORM USABILITY UNTESTED", ini)

    def test_candidate_requires_verified_nodes(self):
        with self.assertRaises(ValueError):
            candidate.build_candidate_ini("custom_proxy_group=🤖 AI"+chr(96)+"select", {})

    def test_actual_generators_preserve_services_and_hk_actual_exit(self):
        root = Path(__file__).resolve().parents[1]
        src = (root / "Clash-Li.ini").read_text(encoding="utf-8")
        new = candidate.build_candidate_ini(src, {
            "TW": ["台湾 01"],
            "HK": ["香港 01", "台湾名字但香港出口"],
            "JP": ["日本(02)"],
            "CA": ["未标注国别 03"],
        })
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "Clash-Li.candidate.ini"
            path.write_text(new, encoding="utf-8")
            android, shadowrocket = candidate.generate_both(str(path))
            for text in (android, shadowrocket):
                self.assertIn(candidate.exit_group("TW"), text)
                self.assertIn(candidate.exit_group("HK"), text)
                self.assertIn(candidate.exit_group("JP"), text)
                self.assertIn(candidate.exit_group("CA"), text)
                self.assertIn(candidate.literal_filter(["香港 01", "台湾名字但香港出口"]), text)
                self.assertIn("Disney+", text)
                self.assertNotIn("🛡️AI 稳态🇹🇼台湾", text)
            self.assertIn("__AIRPORT_URL__", android)
            self.assertTrue((root / "generated" / "Shadowrocket.conf").is_file())

    def test_secure_local_artifact(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "private" / "candidate.ini"
            candidate.secure_write(out, "ok")
            self.assertEqual(out.read_text(), "ok")
            self.assertEqual(out.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
