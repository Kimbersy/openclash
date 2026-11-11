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


def record(name="台湾 01", status="match", cc="TW"):
    return {
        "name": name, "status": status, "claimed_country": cc,
        "observed_country": cc, "observed_ips": ["203.0.113.8"],
        "evidence_sources": ["ipinfo", "ipapi"],
    }


def report(nodes, stamp=None):
    return {
        "schema_version": 1,
        "generated_at": (stamp or datetime.now(timezone.utc)).isoformat(),
        "nodes": nodes,
    }


class VerifiedCandidateTests(unittest.TestCase):
    def test_verified_only(self):
        names = candidate.verified_names(report([
            record("台湾 01"), record("台湾 02", status="mismatch"),
            record("美国 01", cc="US"),
        ]))
        self.assertEqual(names, {"TW": ["台湾 01"], "US": ["美国 01"]})

    def test_reject_expired_future_and_naive(self):
        now = datetime.now(timezone.utc)
        for stamp in (now - timedelta(hours=9), now + timedelta(minutes=6),
                      datetime.now().replace(tzinfo=None)):
            with self.subTest(stamp=stamp), self.assertRaises(ValueError):
                candidate.verified_names(report([record()], stamp), now=now)

    def test_reject_fake_match_evidence(self):
        fake = record()
        fake["evidence_sources"] = ["ipinfo"]
        with self.assertRaises(ValueError):
            candidate.verified_names(report([fake]))
        fake = record()
        fake["observed_country"] = "HK"
        with self.assertRaises(ValueError):
            candidate.verified_names(report([fake]))

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
        self.assertFalse(re.search(p, "台湾02"))

    def test_candidate_ini_preserves_existing_policy(self):
        src = "ruleset=🤖 AI,example\ncustom_proxy_group=🤖 AI" + chr(96) + "select" + chr(96) + "[]🇸🇬新加坡" + chr(96) + "[]🇹🇼台湾\n" + \
              "custom_proxy_group=🏰 Disney+" + chr(96) + "select" + chr(96) + "[]🇸🇬新加坡\n"
        ini = candidate.build_candidate_ini(src, {"TW": ["台湾 01"], "US": ["美国 01"]})
        self.assertIn("[]🇸🇬新加坡", ini)
        self.assertIn("[]🇹🇼台湾", ini)
        self.assertIn("[]🧭核验🇹🇼台湾", ini)
        self.assertIn("[]🧭核验🇺🇸美国", ini)
        self.assertIn("custom_proxy_group=🏰 Disney+", ini)
        self.assertIn("custom_proxy_group=🧭核验🇹🇼台湾", ini)
        self.assertNotIn("203.0.113.8", ini)

    def test_candidate_requires_verified_nodes(self):
        with self.assertRaises(ValueError):
            candidate.build_candidate_ini("custom_proxy_group=🤖 AI" + chr(96) + "select", {})

    def test_actual_generators_on_safe_test_input(self):
        root = Path(__file__).resolve().parents[1]
        src = (root / "Clash-Li.ini").read_text(encoding="utf-8")
        new = candidate.build_candidate_ini(src, {"TW": ["台湾 01"], "JP": ["日本(02)"]})
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "Clash-Li.candidate.ini"
            path.write_text(new, encoding="utf-8")
            android, shadowrocket = candidate.generate_both(str(path))
            self.assertIn("🧭核验🇹🇼台湾", android)
            self.assertIn("🧭核验🇹🇼台湾", shadowrocket)
            self.assertIn("🇹🇼台湾", shadowrocket)
            # Verify full names remain anchored in *generated* filters.
            self.assertIn("(?:^(?:台湾 01)$)", android)
            self.assertIn("(?:^(?:台湾 01)$)", shadowrocket)
            self.assertIn("__AIRPORT_URL__", android)
            # Existing public generated files must not be written or altered.
            self.assertTrue((root / "generated" / "Shadowrocket.conf").is_file())

    def test_secure_local_artifact(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "private" / "candidate.ini"
            candidate.secure_write(out, "ok")
            self.assertEqual(out.read_text(), "ok")
            self.assertEqual(out.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
