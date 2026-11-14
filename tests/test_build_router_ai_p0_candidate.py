"""Synthetic router-only AI fallback isolation tests; no secrets or live calls."""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from ai_service_stability_dry_run import WORKFLOW_TASKS
from build_router_ai_p0_candidate import (
    AUTO, PARENT, HEALTH_URL, fingerprint, build_router_p0_candidate,
)

NOW = datetime(2026, 11, 14, 10, 30, tzinfo=timezone.utc)


def at(minutes):
    return (NOW + timedelta(minutes=minutes)).isoformat()


def example():
    # Deliberately synthetic, never a real airport subscription.
    nodes = [
        {"name": f"TEST_{i}", "type": "trojan", "server": f"example{i}.invalid",
         "port": 443, "password": "FAKE_PRIVATE_SECRET_DO_NOT_PRINT",
         "sni": f"example{i}.invalid", "skip-cert-verify": False}
        for i in range(3)
    ]
    base = {
        "proxies": nodes,
        "proxy-groups": [
            {"name": PARENT, "type": "select",
             "proxies": ["🇹🇼台湾", "🇺🇸美国", "DIRECT", "REJECT"]},
            {"name": "🇹🇼台湾", "type": "select",
             "proxies": ["TEST_0", "TEST_1"]},
            {"name": "🏰 Disney+", "type": "select",
             "proxies": ["🇹🇼台湾", "REJECT"]},
            {"name": "💻 GitHub", "type": "select",
             "proxies": ["🇺🇸美国", "DIRECT"]},
            {"name": "🇺🇸美国", "type": "select", "proxies": ["TEST_2", "REJECT"]},
        ],
        "rules": [
            "DOMAIN-SUFFIX,chatgpt.com,🤖 AI",
            "DOMAIN-SUFFIX,google.com,💻 GitHub",
            "DOMAIN-SUFFIX,disneyplus.com,🏰 Disney+",
            "GEOIP,CN,DIRECT",
            "MATCH,💻 GitHub",
        ],
        "rule-providers": {"non_ai": {"type": "http", "url": "https://example.invalid/list"}},
        "dns": {"enable": True, "nameserver": ["1.1.1.1"]},
        "mode": "rule", "secret": "FAKE_CONTROLLER_SECRET_DO_NOT_PRINT",
    }
    fps = {n["name"]: fingerprint(n) for n in nodes}
    manifest = {
        "schema_version": 1, "generated_at": at(-10),
        "subscription_snapshot": {"sha256": "a"*64, "byte_count": 1000},
        "node_count": 3, "node_fingerprints": fps,
    }
    states, obs = {}, {}
    for i, n in enumerate(nodes):
        name = n["name"]
        fp = fps[name]
        states[name] = {
            "fingerprint": fp,
            "services": {
                svc: {
                    "status": "BUSINESS_VERIFIED", "fingerprint": fp,
                    "method": "user_interactive_workflow",
                    "observed_at": at(-10), "expires_at": at(180),
                    "checks": {step: True for step in steps},
                }
                for svc, steps in WORKFLOW_TASKS.items()
            },
        }
        obs[name] = {
            "fingerprint": fp,
            "egress": {"fingerprint": fp, "verified": True,
                       "country": "TW" if i < 2 else "US",
                       "independent_sources": 2, "observed_at": at(-10)},
            "health": {"fingerprint": fp, "samples": 12,
                       "observed_at": at(-4),
                       "success_rate": 0.99 if i == 0 else 0.995,
                       "rtt_p95_ms": 75 if i == 0 else 130,
                       "throughput_mbps": 40},
        }
    return {
        "config": base, "manifest": manifest, "state": states,
        "observations": obs, "live_names": set(fps) | {"UNTRUSTED_EXTRA"},
        "region": "TW", "now": NOW,
        "source_coverage_verified": True, "runtime_loaded_verified": True,
    }


class RouterP0CandidateTests(unittest.TestCase):
    def build(self, **changes):
        args = example()
        args.update(changes)
        return build_router_p0_candidate(**args)

    def test_two_real_service_qualified_leaves_build_flat_fallback_only(self):
        args = example()
        original = deepcopy(args["config"])
        updated, status = build_router_p0_candidate(**args)
        self.assertEqual(status["status"], "OFFLINE_AI_FALLBACK_CANDIDATE_ONLY")
        self.assertEqual(status["eligible"], 2)
        self.assertEqual(status["selected"], 2)
        self.assertFalse(status["writes"])
        self.assertFalse(status["switch"])
        self.assertEqual(args["config"], original, "No changes to private input")
        self.assertEqual(updated["rules"], original["rules"])
        self.assertEqual(updated["rule-providers"], original["rule-providers"])
        self.assertEqual(updated["proxies"], original["proxies"])
        self.assertEqual(updated["dns"], original["dns"])
        self.assertEqual(updated["secret"], original["secret"])
        self.assertEqual(updated["proxy-groups"][1:-1], original["proxy-groups"][1:])
        self.assertEqual(updated["proxy-groups"][0]["proxies"][:-1],
                         original["proxy-groups"][0]["proxies"])
        self.assertEqual(updated["proxy-groups"][0]["proxies"][-1], AUTO)
        last = updated["proxy-groups"][-1]
        self.assertEqual(last["type"], "fallback")
        self.assertEqual(last["proxies"], ["TEST_1", "TEST_0"])  # stability first
        self.assertTrue(all(x.startswith("TEST_") for x in last["proxies"]))
        self.assertEqual(last["url"], HEALTH_URL)
        self.assertEqual(last["interval"], 300)
        self.assertEqual(last["timeout"], 4000)
        self.assertTrue(last["lazy"])
        # Remains a manual opt-in; existing selected group priority unchanged.
        self.assertEqual(updated["proxy-groups"][0]["proxies"][0], "🇹🇼台湾")
        for private in ("TEST_0", "TEST_1", "UNTRUSTED_EXTRA", "FAKE_PRIVATE_SECRET_DO_NOT_PRINT"):
            self.assertNotIn(private, str(status))

    def test_independent_source_and_runtime_proofs_are_mandatory(self):
        for changes in (
            {"source_coverage_verified": False},
            {"runtime_loaded_verified": False},
            {"source_coverage_verified": False, "runtime_loaded_verified": False},
        ):
            args = example()
            args.update(changes)
            got, report = build_router_p0_candidate(**args)
            self.assertEqual(got, args["config"])
            self.assertEqual(report["status"], "HOLD_INDEPENDENT_SOURCE_OR_RUNTIME_PROOF")

    def test_one_business_proof_or_stale_proof_is_not_enough_for_backup(self):
        args = example()
        args["state"]["TEST_1"]["services"]["notebooklm"]["checks"]["source_imported"] = False
        got, status = build_router_p0_candidate(**args)
        self.assertEqual(status["status"], "HOLD_NO_BUSINESS_VERIFIED_MAIN_AND_BACKUP")
        self.assertEqual(got, args["config"])
        args = example()
        args["state"]["TEST_1"]["services"]["chatgpt"]["method"] = "homepage_http_200"
        got, status = build_router_p0_candidate(**args)
        self.assertEqual(status["status"], "HOLD_NO_BUSINESS_VERIFIED_MAIN_AND_BACKUP")
        args = example()
        args["state"]["TEST_1"]["services"]["notebooklm"]["expires_at"] = at(-1)
        got, status = build_router_p0_candidate(**args)
        self.assertEqual(status["status"], "HOLD_NO_BUSINESS_VERIFIED_MAIN_AND_BACKUP")

    def test_58_plus_extra_unknown_is_not_added_and_never_seen_by_other_groups(self):
        args = example()
        args["live_names"].add("EXTRA_SERVER_999")
        updated, _ = build_router_p0_candidate(**args)
        text = repr(updated["proxy-groups"][-1])
        self.assertNotIn("EXTRA_SERVER_999", text)
        self.assertNotIn("UNTRUSTED_EXTRA", text)
        self.assertEqual(updated["proxy-groups"][-1]["proxies"], ["TEST_1", "TEST_0"])

    def test_stale_egress_untrusted_geo_and_health_cannot_qualify(self):
        for edit in (
            lambda x: x["observations"]["TEST_1"]["egress"].update(verified=False),
            lambda x: x["observations"]["TEST_1"]["egress"].update(observed_at=at(-1600)),
            lambda x: x["observations"]["TEST_1"]["egress"].update(independent_sources=1),
            lambda x: x["observations"]["TEST_1"]["health"].update(samples=1),
            lambda x: x["observations"]["TEST_1"]["health"].update(observed_at=at(-45)),
        ):
            args = example()
            edit(args)
            got, status = build_router_p0_candidate(**args)
            self.assertEqual(got, args["config"])
            self.assertEqual(status["status"], "HOLD_NO_BUSINESS_VERIFIED_MAIN_AND_BACKUP")

    def test_changed_credentials_under_same_name_blocks_entire_candidate(self):
        args = example()
        args["config"]["proxies"][1]["password"] = "NEW_SYNTHETIC_PASSWORD"
        got, status = build_router_p0_candidate(**args)
        self.assertEqual(got, args["config"])
        self.assertEqual(status["status"], "HOLD_FULL_NODE_FINGERPRINT_MISMATCH")
        self.assertNotIn("PASSWORD", str(status))

    def test_name_removed_or_duplicate_and_provider_layout_fail_closed(self):
        args = example()
        args["config"]["proxies"].pop()
        got, r = build_router_p0_candidate(**args)
        self.assertEqual(r["status"], "HOLD_SOURCE_CATALOG_MISMATCH")
        args = example()
        args["config"]["proxies"].append(deepcopy(args["config"]["proxies"][0]))
        got, r = build_router_p0_candidate(**args)
        self.assertEqual(r["status"], "HOLD_AMBIGUOUS_PROXY_IDENTITY")
        args = example()
        args["config"]["proxy-providers"] = {"other": {"type": "http"}}
        got, r = build_router_p0_candidate(**args)
        self.assertEqual(r["status"], "HOLD_UNSUPPORTED_SOURCE_LAYOUT")

    def test_manual_group_absent_or_existing_ai_auto_does_not_get_overwritten(self):
        args = example()
        args["config"]["proxy-groups"][0]["type"] = "url-test"
        got, r = build_router_p0_candidate(**args)
        self.assertEqual(got, args["config"])
        self.assertEqual(r["status"], "HOLD_AI_PARENT_NOT_MANUAL_SELECT")
        args = example()
        args["config"]["proxy-groups"].append({"name": AUTO, "type": "select", "proxies": ["DIRECT"]})
        got, r = build_router_p0_candidate(**args)
        self.assertEqual(got, args["config"])
        self.assertEqual(r["status"], "HOLD_GROUP_NAME_COLLISION")

    def test_group_name_and_node_name_ambiguity_does_not_enter_fallback(self):
        args = example()
        args["config"]["proxy-groups"].append({
            "name": "TEST_1", "type": "select", "proxies": ["TEST_0"]
        })
        original = deepcopy(args["config"])
        got, status = build_router_p0_candidate(**args)
        self.assertEqual(status["status"], "HOLD_NOT_A_DIRECT_LEAF")
        self.assertEqual(got, original)

    def test_same_country_region_lock_is_respected_and_global_not_auto_crossed(self):
        tw, stat = self.build()
        self.assertEqual(tw["proxy-groups"][-1]["proxies"], ["TEST_1", "TEST_0"])
        global_candidate, summary = self.build(region="GLOBAL")
        self.assertEqual(summary["eligible"], 3)
        self.assertEqual(global_candidate["proxy-groups"][-1]["proxies"],
                         ["TEST_1", "TEST_2", "TEST_0"])

    def test_fallback_does_not_use_direct_reject_or_shared_country_group(self):
        args = example()
        args["config"]["proxies"][1]["type"] = "select"
        args["manifest"]["node_fingerprints"]["TEST_1"] = fingerprint(args["config"]["proxies"][1])
        args["state"]["TEST_1"]["fingerprint"] = args["manifest"]["node_fingerprints"]["TEST_1"]
        args["observations"]["TEST_1"]["fingerprint"] = args["manifest"]["node_fingerprints"]["TEST_1"]
        args["state"]["TEST_1"]["services"] = {
            k: dict(v, fingerprint=args["manifest"]["node_fingerprints"]["TEST_1"])
            for k, v in args["state"]["TEST_1"]["services"].items()
        }
        args["observations"]["TEST_1"]["egress"]["fingerprint"] = args["manifest"]["node_fingerprints"]["TEST_1"]
        args["observations"]["TEST_1"]["health"]["fingerprint"] = args["manifest"]["node_fingerprints"]["TEST_1"]
        got, r = build_router_p0_candidate(**args)
        self.assertEqual(got, args["config"])
        self.assertEqual(r["status"], "HOLD_NOT_A_DIRECT_LEAF")


if __name__ == "__main__":
    unittest.main()
