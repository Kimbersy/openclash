"""Synthetic whole-active-subscription -> all service/region pools -> refresh DRY_RUN.

Never uses real credentials, subscription addresses, controller calls, routers.
Inherited business proofs remain valid ONLY when the exact fingerprint survives
and the existing dated proof validator accepts each service.
"""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_full_region_refresh_dry_run import (
    group_name, plan_full_ai_region_refresh
)
from build_router_ai_p0_candidate import PARENT, fingerprint
from test_build_router_ai_p0_candidate import example, NOW, at

SIGNALS = {
    "update_event": "NO_CHANGE",
    "source_changed": False,
    "source_runtime_disk_equal": True,
    "live_api_reachable": True,
    "live_membership_matches": True,
    "full_runtime_reload_confirmed": True,
    "stable_snapshot_samples": 2,
    "non_ai_changes": 0,
}


def context():
    x = example()
    manifest = deepcopy(x["manifest"])
    return {
        "config": x["config"],
        "previous_manifest": manifest,
        "current_manifest": deepcopy(manifest),
        "previous_state": x["state"],
        "observations": x["observations"],
        "live_names": x["live_names"],
        "refresh_signals": deepcopy(SIGNALS),
        "coverage_verified": True,
        "now": NOW,
    }


def plan(x):
    return plan_full_ai_region_refresh(**x)


def group_list(output):
    return output["private_candidate"]["proxy-groups"]


def names(groups):
    return {g["name"]: g for g in groups}


def make_changed(x):
    x["refresh_signals"]["update_event"] = "UPDATED"
    x["refresh_signals"]["source_changed"] = True
    x["current_manifest"]["subscription_snapshot"]["sha256"] = "b" * 64


class FullRegionRefreshTests(unittest.TestCase):
    def test_global_and_every_verified_country_for_three_services_are_materialized(self):
        x = context()
        before = deepcopy(x["config"])
        result = plan(x)
        p = result["public"]
        self.assertEqual(p["decision"], "OFFLINE_CANDIDATE_ONLY")
        self.assertEqual(p["source_total"], 3)
        self.assertEqual(p["verified_country_count"], 2)
        self.assertEqual(p["shared_three_service_nodes"], 3)
        self.assertEqual(p["qualified_group_count"], 12)
        self.assertFalse(p["live_apply"])
        self.assertFalse(p["switch"])
        self.assertFalse(p["non_ai_mutation"])
        self.assertEqual(x["config"], before)
        generated = result["private_candidate"]
        for key in ("proxies", "rules", "dns", "rule-providers", "secret"):
            self.assertEqual(before[key], generated[key])
        self.assertEqual(before["proxy-groups"][1:], generated["proxy-groups"][1:5])
        parent = generated["proxy-groups"][0]
        self.assertEqual(parent["proxies"][:len(before["proxy-groups"][0]["proxies"])],
                         before["proxy-groups"][0]["proxies"])
        self.assertEqual(parent["proxies"][-3:],
                         [group_name("shared_all_services", cc)
                          for cc in ("GLOBAL", "TW", "US")])
        g = names(group_list(result))
        self.assertEqual(g[group_name("shared_all_services", "GLOBAL")]["proxies"],
                         ["TEST_1", "TEST_2", "TEST_0"])
        self.assertEqual(g[group_name("shared_all_services", "TW")]["proxies"],
                         ["TEST_1", "TEST_0"])
        self.assertEqual(g[group_name("shared_all_services", "TW")]["type"], "fallback")
        self.assertEqual(g[group_name("shared_all_services", "US")]["type"], "select")
        self.assertEqual(g[group_name("chatgpt", "US")]["proxies"], ["TEST_2"])
        # Service-specific pools exist in private generated config but never
        # become shared AI parent options, which would split Google sessions.
        self.assertNotIn(group_name("gemini", "TW"), parent["proxies"])
        self.assertNotIn(group_name("notebooklm", "US"), parent["proxies"])

    def test_all_seven_tw_leaves_are_retained_not_first_three(self):
        x = context()
        for i in range(3, 8):
            n = deepcopy(x["config"]["proxies"][0])
            n["name"] = f"TEST_{i}"
            n["server"] = f"example{i}.invalid"
            n["sni"] = f"example{i}.invalid"
            x["config"]["proxies"].append(n)
            fp = fingerprint(n)
            x["current_manifest"]["node_fingerprints"][n["name"]] = fp
            x["previous_manifest"]["node_fingerprints"][n["name"]] = fp
            x["live_names"].add(n["name"])
            st = deepcopy(x["previous_state"]["TEST_0"])
            st["fingerprint"] = fp
            for proof in st["services"].values():
                proof["fingerprint"] = fp
            x["previous_state"][n["name"]] = st
            obs = deepcopy(x["observations"]["TEST_0"])
            obs["fingerprint"] = fp
            obs["egress"]["fingerprint"] = fp
            obs["health"]["fingerprint"] = fp
            x["observations"][n["name"]] = obs
        for key in ("previous_manifest", "current_manifest"):
            x[key]["node_count"] = len(x[key]["node_fingerprints"])
        res = plan(x)
        self.assertEqual(res["public"]["shared_three_service_nodes"], 8)
        self.assertEqual(len(names(group_list(res))[group_name("shared_all_services", "TW")]["proxies"]), 7)
        self.assertEqual(res["public"]["qualified_leaf_count"], 8)

    def test_single_service_node_kept_even_when_shared_intersection_shrinks(self):
        x = context()
        x["previous_state"]["TEST_1"]["services"]["notebooklm"]["checks"]["source_imported"] = False
        res = plan(x)
        g = names(group_list(res))
        self.assertNotIn("TEST_1", g[group_name("shared_all_services", "GLOBAL")]["proxies"])
        self.assertIn("TEST_1", g[group_name("chatgpt", "GLOBAL")]["proxies"])
        self.assertIn("TEST_1", g[group_name("gemini", "TW")]["proxies"])

    def test_incremental_added_node_is_queued_not_inherited_before_business_proof(self):
        x = context()
        make_changed(x)
        new = deepcopy(x["config"]["proxies"][0])
        new.update(name="NEW_4", server="new.example.invalid", sni="new.example.invalid")
        x["config"]["proxies"].append(new)
        fp = fingerprint(new)
        x["current_manifest"]["node_fingerprints"]["NEW_4"] = fp
        x["current_manifest"]["node_count"] += 1
        x["live_names"].add("NEW_4")
        # Previous state can include stale/spoofed data for the new name; it
        # must not carry forward without matching previous manifest identity.
        x["previous_state"]["NEW_4"] = deepcopy(x["previous_state"]["TEST_0"])
        x["previous_state"]["NEW_4"]["fingerprint"] = fp
        for p in x["previous_state"]["NEW_4"]["services"].values():
            p["fingerprint"] = fp
        newobs = deepcopy(x["observations"]["TEST_0"])
        newobs["fingerprint"] = fp
        newobs["egress"]["fingerprint"] = fp
        newobs["health"]["fingerprint"] = fp
        x["observations"]["NEW_4"] = newobs
        r = plan(x)
        self.assertEqual(r["public"]["source_added"], 1)
        self.assertEqual(r["public"]["shared_three_service_nodes"], 3)
        self.assertEqual(r["private_probe_queue"], ["NEW_4"])
        self.assertEqual(r["private_state"]["NEW_4"]["services"]["chatgpt"]["status"], "UNKNOWN")

    def test_removed_node_disappears_from_all_country_and_service_pools(self):
        x = context()
        make_changed(x)
        x["config"]["proxies"] = [n for n in x["config"]["proxies"] if n["name"] != "TEST_2"]
        del x["current_manifest"]["node_fingerprints"]["TEST_2"]
        x["current_manifest"]["node_count"] -= 1
        x["live_names"].discard("TEST_2")
        r = plan(x)
        self.assertEqual(r["public"]["source_removed"], 1)
        self.assertEqual(r["public"]["verified_country_count"], 1)
        self.assertEqual(r["public"]["qualified_group_count"], 8)
        self.assertNotIn(group_name("shared_all_services", "US"), names(group_list(r)))
        self.assertNotIn("TEST_2", r["private_state"])

    def test_changed_same_name_credentials_revokes_old_business_qualification(self):
        x = context()
        make_changed(x)
        n = x["config"]["proxies"][1]
        n["password"] = "SYNTHETIC_ROTATED_NOT_REAL"
        newfp = fingerprint(n)
        x["current_manifest"]["node_fingerprints"]["TEST_1"] = newfp
        r = plan(x)
        self.assertEqual(r["public"]["source_replaced_same_name"], 1)
        self.assertIn("TEST_1", r["private_probe_queue"])
        self.assertNotIn("TEST_1", names(group_list(r))[group_name("shared_all_services", "GLOBAL")]["proxies"])
        self.assertEqual(r["private_state"]["TEST_1"]["services"]["notebooklm"]["status"], "UNKNOWN")
        self.assertNotIn("SYNTHETIC_ROTATED", repr(r["public"]))

    def test_comment_only_raw_snapshot_update_preserves_valid_evidence(self):
        x = context()
        make_changed(x)
        x["config"]["proxies"].reverse()
        r = plan(x)
        self.assertEqual(r["public"]["source_replaced_same_name"], 0)
        self.assertEqual(r["public"]["retained_service_evidence"], 9)
        self.assertEqual(r["private_probe_queue"], [])
        self.assertEqual(r["public"]["shared_three_service_nodes"], 3)

    def test_update_failure_missing_runtime_proof_non_ai_change_preserves_original(self):
        for patch in (
            lambda x: x["refresh_signals"].update(update_event="ERROR"),
            lambda x: x["refresh_signals"].update(full_runtime_reload_confirmed=False),
            lambda x: x["refresh_signals"].update(non_ai_changes=1),
            lambda x: x.update(coverage_verified=False),
            lambda x: x["refresh_signals"].update(source_runtime_disk_equal=False),
        ):
            x = context()
            old = deepcopy(x["config"])
            patch(x)
            r = plan(x)
            self.assertTrue(r["public"]["decision"].startswith("HOLD_"))
            self.assertEqual(r["private_candidate"], old)
            self.assertIsNone(r["private_state"])
            self.assertEqual(r["private_probe_queue"], [])
            self.assertFalse(r["public"]["live_apply"])

    def test_unverified_runtime_name_and_unknown_extra_cannot_enter_pools(self):
        x = context()
        x["live_names"].add("EXTRA_UNTRUSTED_NOT_IN_MANIFEST")
        r = plan(x)
        self.assertEqual(r["public"]["extra_live_untrusted"], 2)
        self.assertEqual(r["public"]["shared_three_service_nodes"], 3)
        self.assertNotIn("EXTRA_UNTRUSTED", repr(r["private_candidate"]["proxy-groups"]))
        x["live_names"].remove("TEST_1")
        r = plan(x)
        self.assertEqual(r["public"]["decision"], "HOLD_RUNTIME_MEMBERSHIP_MISMATCH")

    def test_future_provider_needs_separate_runtime_evidence_not_silent_drop(self):
        x = context()
        x["config"]["proxy-providers"] = {"future": {"type": "http", "url": "https://example.invalid"}}
        r = plan(x)
        self.assertEqual(r["public"]["decision"], "HOLD_PROVIDER_SUPPORT_NOT_ATTESTED")
        self.assertEqual(r["private_candidate"], x["config"])

    def test_non_ai_group_collision_refuses_generation(self):
        x = context()
        x["config"]["proxy-groups"].append({
            "name": group_name("shared_all_services", "TW"), "type": "select",
            "proxies": ["DIRECT"],
        })
        r = plan(x)
        self.assertEqual(r["public"]["decision"], "HOLD_AI_NAME_COLLISION")
        self.assertEqual(r["private_candidate"], x["config"])

    def test_fake_event_inconsistent_snapshot_refuses_generation(self):
        x = context()
        x["current_manifest"]["subscription_snapshot"]["sha256"] = "b" * 64
        r = plan(x)
        self.assertEqual(r["public"]["decision"], "HOLD_EVENT_SNAPSHOT_MISMATCH")
        x = context()
        x["refresh_signals"]["source_changed"] = True
        x["refresh_signals"]["update_event"] = "UPDATED"
        r = plan(x)
        self.assertEqual(r["public"]["decision"], "HOLD_EVENT_SNAPSHOT_MISMATCH")

    def test_anonymous_only_status_does_not_publish_source_or_node_data(self):
        x = context()
        r = plan(x)
        status = repr(r["public"])
        for private in ("TEST_0", "TEST_1", "TEST_2", "FAKE_PRIVATE_SECRET",
                        "UNTRUSTED_EXTRA", "example0.invalid", "a"*64):
            self.assertNotIn(private, status)


if __name__ == "__main__":
    unittest.main()
