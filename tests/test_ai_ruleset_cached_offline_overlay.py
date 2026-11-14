"""Offline 20/20 cached-http rule-provider private file overlay gates."""
import sys
import unittest
from copy import deepcopy
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from ai_ruleset_cached_offline_overlay import private_file_overlay

FAKE_SECRET = "SYNTHETIC_PRIVATE_TOKEN_NOT_FOR_LOG"


def fixture(n=20):
    providers = {}
    files = {}
    for i in range(n):
        name = f"RULE_{i:02d}"
        providers[name] = {
            "type": "http", "url": f"https://fake:{FAKE_SECRET}@example.invalid/rules/{i}",
            "path": f"./rules/{i:02d}.yaml",
            "interval": 86400, "behavior": "classical", "format": "yaml",
        }
        files[name] = b"payload:\n  - 'DOMAIN-SUFFIX,static.example.invalid'\n"
    cfg = {
        "mode": "rule", "allow-lan": False, "mixed-port": 7890,
        "proxies": [{"name": "TEST_0", "type": "http", "server": "192.0.2.1", "port": 8080}],
        "proxy-groups": [
            {"name": "🤖 AI", "type": "select", "proxies": ["TEST_0", "DIRECT"]},
            {"name": "Disney+", "type": "select", "proxies": ["DIRECT"]}],
        "rule-providers": providers,
        "rules": ["RULE-SET,RULE_00,🤖 AI", "MATCH,DIRECT"],
        "dns": {"enable": False},
        "secret": FAKE_SECRET,
    }
    return cfg, files


class TestPrivateCacheOverlay(unittest.TestCase):
    def test_twenty_provider_cached_bytes_preserved_and_nonai_unchanged(self):
        cfg, files = fixture()
        original = deepcopy(cfg)
        artifact, status = private_file_overlay(cfg, files)
        self.assertEqual(status["decision"], "OFFLINE_PRIVATE_FILE_PROVIDER_SYNTAX_CANDIDATE")
        self.assertEqual(status["file_provider_conversions"], 20)
        self.assertFalse(status["installed"])
        self.assertFalse(status["network_requests"])
        self.assertFalse(status["business_verified"])
        self.assertEqual(cfg, original)
        self.assertEqual(artifact["config"]["proxies"], original["proxies"])
        self.assertEqual(artifact["config"]["rules"], original["rules"])
        self.assertEqual(artifact["config"]["dns"], original["dns"])
        self.assertEqual(artifact["config"]["secret"], original["secret"])
        self.assertEqual(artifact["config"]["proxy-groups"][:-1], original["proxy-groups"])
        self.assertEqual(artifact["config"]["listeners"], [{
            "name": "ai-notebook-probe-only", "type": "http",
            "listen": "127.0.0.1", "port": 17881,
            "proxy": "__AI_NOTEBOOK_PROBE_ONLY__",
        }])
        self.assertEqual(len(artifact["cache_files"]), 20)
        self.assertCountEqual(artifact["cache_files"].values(), files.values())
        self.assertTrue(all(v["type"] == "file" for v in artifact["config"]["rule-providers"].values()))
        for value in artifact["config"]["rule-providers"].values():
            self.assertNotIn("url", value)
            self.assertNotIn("interval", value)
        self.assertNotIn(FAKE_SECRET, repr(status))

    def test_missing_or_unchecked_cached_content_holds(self):
        cfg, files = fixture()
        files.pop("RULE_19")
        self.assertEqual(private_file_overlay(cfg, files)[1]["decision"], "HOLD_CACHE_IDENTITY_MISMATCH")
        files["RULE_19"] = b""
        self.assertEqual(private_file_overlay(cfg, files)[1]["decision"], "HOLD_CACHE_BYTES_UNVERIFIED")
        files["RULE_19"] = b"x" * (8 * 1024 * 1024 + 1)
        self.assertEqual(private_file_overlay(cfg, files)[1]["decision"], "HOLD_CACHE_BYTES_UNVERIFIED")

    def test_geo_flag_from_user_receipt_must_not_auto_pass(self):
        cfg, files = fixture()
        for key, value in (("geodata-mode", True), ("geo-auto-update", True),
                           ("geox-url", {"geoip": "https://secret.invalid/geoip.dat"})):
            c = deepcopy(cfg)
            c[key] = value
            self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_GEO_RESOURCE_NOT_MIRRORED")
        cfg["rules"] = ["GEOIP,CN,DIRECT", "RULE-SET,RULE_00,🤖 AI", "MATCH,DIRECT"]
        self.assertEqual(private_file_overlay(cfg, files)[1]["decision"], "HOLD_GEO_RULE_NOT_MIRRORED")

    def test_provider_path_traversal_and_bundle_fail_closed(self):
        cfg, files = fixture()
        for p in ("/etc/openclash/private.yaml", "../secrets.yaml", "rules/../../bad",
                  "", "rules/\x00bad"):
            c = deepcopy(cfg)
            c["rule-providers"]["RULE_00"]["path"] = p
            self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_PROVIDER_PATH")
        c = deepcopy(cfg)
        c["rule-providers"]["RULE_00"]["path-in-bundle"] = "rule/private"
        self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_PROVIDER_BUNDLE")

    def test_provider_identity_behavior_format_and_source_cannot_be_faked(self):
        cfg, files = fixture()
        c = deepcopy(cfg)
        c["rule-providers"]["RULE_00"]["behavior"] = "weird"
        self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_PROVIDER_FORMAT")
        c = deepcopy(cfg)
        c["rule-providers"]["RULE_00"]["url"] = "http://token.invalid"
        self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_PROVIDER_ORIGIN")
        c = deepcopy(cfg)
        c["proxy-providers"] = {"unverified": {"type": "http"}}
        self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_PROXY_SOURCE_LAYOUT")
        c = deepcopy(cfg)
        c["proxy-groups"][0]["use"] = ["unverified"]
        self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_PROXY_SOURCE_LAYOUT")
        c = deepcopy(cfg)
        c["proxy-groups"][0]["type"] = "fallback"
        self.assertEqual(private_file_overlay(c, files)[1]["decision"], "HOLD_AI_PARENT")

    def test_cache_budget_caps_large_cold_catalog_without_truncating(self):
        cfg, files = fixture(80)
        artifact, status = private_file_overlay(cfg, files)
        self.assertEqual(status["file_provider_conversions"], 80)
        self.assertEqual(len(artifact["cache_files"]), 80)
        self.assertEqual(len(artifact["config"]["proxy-groups"][-1]["proxies"]), 2)
        files = {key: b"x" * (700 * 1024) for key in files}
        self.assertEqual(private_file_overlay(cfg, files)[1]["decision"], "HOLD_CACHE_BUDGET")


if __name__ == "__main__":
    unittest.main()
