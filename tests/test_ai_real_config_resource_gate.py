"""Synthetic-only fail-closed resource audit. No router secrets or subprocesses."""
import sys
import unittest
from copy import deepcopy
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from ai_real_config_resource_gate import audit_resources

SECRET = "SYNTHETIC_SECRET_NEVER_PRINT"

def fixture():
    return {
        "geodata-mode": False, "geo-auto-update": False,
        "geox-url": {"mmdb": "https://fake.invalid/country.mmdb"},
        "rule-providers": {
            f"rule_{i:02d}": {"type": "http",
                             "path": f"./rules/cache_{i}.yaml",
                             "url": f"https://{SECRET}@example.invalid/{i}"}
            for i in range(20)},
        "proxy-groups": [{"name": "🤖 AI", "type": "select", "proxies": ["abc"]}],
        "rules": ["RULE-SET,rule_00,🤖 AI", "MATCH,DIRECT"],
        "dns": {"enable": True, "nameserver": ["https://dns.example.invalid/dns-query"]},
        "proxies": [{"type": "http", "name": "abc", "password": SECRET}],
        "secret": SECRET
    }

class ResourceGateTests(unittest.TestCase):
    def test_17_20_shape_holds_without_network_sandbox(self):
        cfg = fixture()
        original = deepcopy(cfg)
        res = audit_resources(cfg)
        self.assertEqual(res["decision"], "HOLD_NETWORK_ISOLATION_UNPROVEN")
        self.assertEqual(res["cached_http_rule_providers"], 20)
        self.assertTrue(res["custom_geo_url_present"])
        for field in ("may_invoke_mihomo", "can_make_network_request",
                      "production_writes", "user_secrets_returned"):
            self.assertFalse(res[field])
        self.assertNotIn(SECRET, repr(res))
        self.assertEqual(cfg, original)

    def test_hidden_nested_geosite_and_dns_geo_require_hold(self):
        for key, value in (
            ("nameserver-policy", {"geosite:cn": ["https://dns.invalid"]}),
            ("fake-ip-filter", ["geosite:private"]),
            ("fallback-filter", {"geoip": True, "geoip-code": "CN"}),
        ):
            cfg = fixture()
            cfg["dns"][key] = value
            expected = ("HOLD_DNS_GEO_FALLBACK" if key == "fallback-filter"
                        else "HOLD_NESTED_GEO_REFERENCE")
            self.assertEqual(audit_resources(cfg)["decision"], expected)
        cfg = fixture()
        cfg["sniffer"] = {"skip-domain": ["geosite:private"]}
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_NESTED_GEO_REFERENCE")

    def test_geo_flags_and_main_rules_must_not_be_silently_dropped(self):
        for key in ("geodata-mode", "geo-auto-update"):
            cfg = fixture()
            cfg[key] = True
            self.assertEqual(audit_resources(cfg)["decision"], "HOLD_GEO_MODE_CHANGED")
        cfg = fixture()
        cfg.pop("geox-url")
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_GEO_SOURCE_CHANGED")
        cfg = fixture()
        cfg["geox-url"] = "unsafe-string"
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_GEO_URL_LAYOUT")
        cfg = fixture()
        cfg["rules"].insert(0, "GEOIP,CN,DIRECT")
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_GEO_RULE_REFERENCE")

    def test_provider_and_group_references_hold(self):
        cfg = fixture()
        cfg["proxy-providers"] = {"unexpected": {"type": "http"}}
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_PROXY_PROVIDERS")
        cfg = fixture()
        cfg["proxy-groups"][0]["use"] = ["unexpected"]
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_PROXY_PROVIDER_GROUP_REFERENCE")
        cfg = fixture()
        cfg["rule-providers"]["rule_00"]["type"] = "inline"
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_RULE_PROVIDER_SOURCE")

    def test_other_external_assets_and_unknown_layouts_hold(self):
        for key, value in (("external-ui-url", "https://fake.invalid/ui.zip"),
                           ("script", {"code": "x"}), ("sub-rules", {})):
            cfg = fixture()
            cfg[key] = value
            self.assertEqual(audit_resources(cfg)["decision"], "HOLD_OTHER_EXTERNAL_RESOURCE")
        for cfg in (None, "bad", []):
            self.assertEqual(audit_resources(cfg)["decision"], "HOLD_CONFIG_LAYOUT")
        cfg = fixture()
        cfg["dns"] = []
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_DNS_LAYOUT")

    def test_excessive_nesting_fail_closed(self):
        cfg = fixture()
        nested = "ordinary"
        for _ in range(50):
            nested = [nested]
        cfg["dns"]["unknown"] = nested
        self.assertEqual(audit_resources(cfg)["decision"], "HOLD_NESTED_GEO_REFERENCE")

if __name__ == "__main__":
    unittest.main()
