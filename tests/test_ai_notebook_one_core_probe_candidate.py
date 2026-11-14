"""No-router one-core Mihomo listener / private-selector isolation tests."""
from copy import deepcopy
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from ai_notebook_one_core_probe_candidate import (
    candidate_one_core_probe_listener, AI_PARENT, GROUP_NAME, LISTEN,
    LISTENER_NAME, PORT,
)
from test_build_router_ai_p0_candidate import example


def fixture():
    original = example()["config"]
    original.update({"mixed-port": 7890, "socks-port": 7891})
    return original


class TestOneCoreNotebookProbeCandidate(unittest.TestCase):
    def build(self, config=None, *, verified=True):
        return candidate_one_core_probe_listener(
            fixture() if config is None else config,
            source_identity_verified=verified,
        )

    def test_one_listener_idle_selector_no_shared_ai_or_non_ai_side_effect(self):
        original = fixture()
        frozen = deepcopy(original)
        out, status = self.build(original)
        self.assertEqual(original, frozen)
        self.assertEqual(status["decision"], "OFFLINE_ISOLATED_LISTENER_CANDIDATE_ONLY")
        self.assertTrue(status["loopback_only"])
        self.assertTrue(status["starts_disabled"])
        self.assertFalse(status["live_writes"])
        self.assertFalse(status["controller_put"])
        self.assertFalse(status["switch"])
        self.assertFalse(status["actual_device_validated"])
        self.assertEqual(status["isolated_listener_count"], 1)
        self.assertEqual(status["probe_leaf_count"], 3)
        self.assertEqual(out["proxies"], frozen["proxies"])
        for key in ("rules", "rule-providers", "dns", "secret", "mixed-port", "socks-port"):
            self.assertEqual(out[key], frozen[key])
        self.assertEqual(out["proxy-groups"][:-1], frozen["proxy-groups"])
        self.assertEqual(out["proxy-groups"][0], frozen["proxy-groups"][0])
        self.assertEqual(out["proxy-groups"][-1], {
            "name": GROUP_NAME, "type": "select",
            "proxies": ["REJECT", "TEST_0", "TEST_1", "TEST_2"],
        })
        self.assertEqual(out["listeners"], [{
            "name": LISTENER_NAME, "type": "http",
            "listen": "127.0.0.1", "port": PORT, "proxy": GROUP_NAME,
        }])
        for leaked in ("TEST_0", "FAKE_PRIVATE_SECRET_DO_NOT_PRINT", "example0.invalid"):
            self.assertNotIn(leaked, repr(status))

    def test_all_inline_nodes_are_candidates_not_truncated_at_three(self):
        config = fixture()
        for i in range(3, 70):
            config["proxies"].append({
                "name": f"TEST_{i}", "type": "trojan",
                "server": f"example{i}.invalid", "port": 443,
                "password": "SYNTHETIC", "sni": f"example{i}.invalid",
            })
        out, status = self.build(config)
        self.assertEqual(status["probe_leaf_count"], 70)
        self.assertEqual(len(out["proxy-groups"][-1]["proxies"]), 71)
        self.assertEqual(out["proxy-groups"][-1]["proxies"][0], "REJECT")
        self.assertIn("TEST_69", out["proxy-groups"][-1]["proxies"])

    def test_requires_independently_verified_source_identity(self):
        config = fixture()
        out, status = self.build(config, verified=False)
        self.assertEqual(out, config)
        self.assertEqual(status["decision"], "HOLD_SOURCE_IDENTITY_UNVERIFIED")

    def test_existing_local_port_or_listener_name_is_not_overwritten(self):
        for mutate, expected in (
            (lambda cfg: cfg.update({"mixed-port": PORT}), "HOLD_PORT_COLLISION"),
            (lambda cfg: cfg.update({"listeners": [
                {"name": "other", "type": "http", "listen": "127.0.0.1", "port": PORT}
            ]}), "HOLD_PORT_COLLISION"),
            (lambda cfg: cfg.update({"listeners": [
                {"name": LISTENER_NAME, "type": "http", "listen": "127.0.0.1", "port": 18080}
            ]}), "HOLD_LISTENER_NAME_CONFLICT"),
        ):
            cfg = fixture()
            mutate(cfg)
            out, status = self.build(cfg)
            self.assertEqual(status["decision"], expected)
            self.assertEqual(out, cfg)

    def test_name_collisions_and_bad_parent_fail_closed(self):
        for mutate, expected in (
            (lambda cfg: cfg["proxy-groups"].append({
                "name": GROUP_NAME, "type": "select", "proxies": ["DIRECT"],
            }), "HOLD_GROUP_NAME_CONFLICT"),
            (lambda cfg: cfg["proxies"].append(deepcopy(cfg["proxies"][0])),
             "HOLD_DUPLICATE_NODE_NAME"),
            (lambda cfg: cfg["proxy-groups"][0].update(type="fallback"),
             "HOLD_ORIGINAL_AI_PARENT_CHANGED"),
            (lambda cfg: cfg["proxy-groups"].append({
                "name": "TEST_0", "type": "select", "proxies": ["TEST_1"]
            }), "HOLD_GROUP_NAME_CONFLICT"),
        ):
            cfg = fixture()
            mutate(cfg)
            out, status = self.build(cfg)
            self.assertEqual(out, cfg)
            self.assertEqual(status["decision"], expected)

    def test_provider_and_unknown_listener_port_never_silently_disappear(self):
        cfg = fixture()
        cfg["proxy-providers"] = {"future": {"type": "http"}}
        out, status = self.build(cfg)
        self.assertEqual(status["decision"], "HOLD_PROVIDER_LOADED_PROOF_MISSING")
        self.assertEqual(out, cfg)

        cfg = fixture()
        cfg["listeners"] = [{"name": "other", "port": "5000-6000", "type": "mixed"}]
        out, status = self.build(cfg)
        self.assertEqual(status["decision"], "HOLD_UNVERIFIED_LISTENER_PORT")
        self.assertEqual(out, cfg)

    def test_no_private_selector_in_ai_group_or_other_rule(self):
        out, _ = self.build()
        for group in out["proxy-groups"][:-1]:
            self.assertNotIn(GROUP_NAME, group["proxies"])
        for item in out["rules"]:
            self.assertNotIn(GROUP_NAME, item)
        self.assertNotIn(GROUP_NAME, out["proxy-groups"][0]["proxies"])
        self.assertEqual(out["listeners"][0]["proxy"], GROUP_NAME)
        self.assertEqual(LISTEN, "127.0.0.1")

    def test_no_proxy_mutating_or_runtime_side_effects_in_source(self):
        source = (pathlib.Path(__file__).resolve().parents[1] /
                  "scripts/ai_notebook_one_core_probe_candidate.py").read_text()
        self.assertNotIn("requests.put(", source)
        self.assertNotIn("subprocess.run(", source)
        self.assertNotIn("urllib.request.urlopen", source)


if __name__ == "__main__":
    unittest.main()
