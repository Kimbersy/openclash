"""Synthetic, privacy-safe regression for service-specific AI anti-flap DRY_RUN."""
import copy
import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_service_stability_dry_run import plan_dry_run, WORKFLOW_TASKS, business_verified

NOW = datetime(2026, 11, 14, 3, 0, tzinfo=timezone.utc)


def ts(minutes=0):
    return (NOW + timedelta(minutes=minutes)).isoformat()


def manifest(nodes):
    return {
        "schema_version": 1,
        "generated_at": ts(-10),
        "subscription_snapshot": {"sha256": "a"*64, "byte_count": 9000},
        "node_count": len(nodes),
        "node_fingerprints": nodes,
    }


def successful_refresh():
    return {
        "update_event": "NO_CHANGE", "source_changed": False,
        "source_runtime_disk_equal": True, "live_api_reachable": True,
        "live_membership_matches": True, "full_runtime_reload_confirmed": True,
        "stable_snapshot_samples": 2, "non_ai_changes": 0,
    }


def evidence(fp, service, *, complete=True, method="user_interactive_workflow",
             status="BUSINESS_VERIFIED", expiry=360):
    checks = {task: True for task in WORKFLOW_TASKS[service]}
    if not complete:
        checks[next(iter(checks))] = False
    return {
        "fingerprint": fp, "status": status, "method": method,
        "checks": checks, "observed_at": ts(-20), "expires_at": ts(expiry),
    }


def record(fp, *, country="TW", rate=0.999, rtt=120, health_age=-5,
           verified=True, sources=2):
    return {
        "fingerprint": fp,
        "cost_multiplier": 1.0,
        "egress": {"fingerprint": fp, "country": country,
                   "verified": verified, "independent_sources": sources,
                   "observed_at": ts(-15)},
        "health": {"fingerprint": fp, "samples": 20,
                   "success_rate": rate, "rtt_p95_ms": rtt,
                   "throughput_mbps": 25, "observed_at": ts(health_age)},
    }


def failures(current, fp):
    return [
        {"node": current, "fingerprint": fp,
         "kind": "node_network", "target": target, "observed_at": ts(-i)}
        for i, target in ((0.3, "http"), (0.7, "tls"), (1.1, "dns"))
    ]


def scenario():
    # Synthetic historical 58/58 + one unknown extra live API name, not real credentials.
    nodes = {f"synthetic_{i:02}": f"{i+1:064x}" for i in range(58)}
    m = manifest(nodes)
    st = {}
    obs = {}
    for name in ("synthetic_00", "synthetic_01"):
        fp = nodes[name]
        st[name] = {"fingerprint": fp, "services": {
            svc: evidence(fp, svc) for svc in WORKFLOW_TASKS
        }}
        obs[name] = record(fp)
    args = {
        "previous_manifest": m, "current_manifest": m,
        "previous_state": st, "observations": obs,
        "live_names": set(nodes) | {"unverified_extra_leaf"},
        "refresh_signals": successful_refresh(), "coverage_verified": True,
        "service": "chatgpt", "region": "TW",
        "current": "synthetic_00", "mode": "AUTO",
        "ai_parent_selected_stable": True, "state_history_ready": True,
        "current_healthy": False, "global_incident": False,
        "selected_since": ts(-60), "cooldown_until": ts(-1),
        "failure_events": failures("synthetic_00", nodes["synthetic_00"]),
        "now": NOW,
    }
    return args


class StableServiceDryRunTests(unittest.TestCase):
    def decision(self, **override):
        args = scenario()
        args.update(override)
        return plan_dry_run(**args)

    def test_58_in_memory_names_plus_one_extra_are_not_all_eligible(self):
        result = self.decision()
        self.assertEqual(result["public"]["expected_names"], 58)
        self.assertEqual(result["public"]["present_names"], 58)
        self.assertEqual(result["public"]["extra_untrusted"], 1)
        self.assertEqual(result["public"]["qualified_candidates"], 2)
        self.assertEqual(result["public"]["decision"], "DRY_RUN_SWITCH_CANDIDATE")
        self.assertEqual(result["private_target"], "synthetic_01")
        self.assertNotIn("synthetic_01", str(result["public"]))
        self.assertNotIn("unverified_extra_leaf", str(result["public"]))
        self.assertFalse(result["public"]["live_writes"])
        self.assertFalse(result["public"]["ai_switch"])

    def test_actual_2352_receipt_cannot_unlock_reconciliation_or_switch(self):
        args = scenario()
        args["refresh_signals"].update({
            "update_event": "UNKNOWN",
            "source_changed": False,
            "full_runtime_reload_confirmed": False,
            "live_membership_matches": False,  # 58/58 names are not full identity
        })
        res = plan_dry_run(**args)
        self.assertEqual(res["public"]["gate"], "HOLD_UPDATE_UNCONFIRMED")
        self.assertEqual(res["public"]["decision"], "HOLD_UPDATE_EVIDENCE")
        self.assertEqual(res["public"]["qualified_candidates"], 0)
        self.assertIsNone(res["private_target"])

    def test_missing_reload_proof_even_with_updated_log_is_blocked(self):
        signals = successful_refresh()
        signals.update({"update_event": "UPDATED", "source_changed": True,
                        "full_runtime_reload_confirmed": False})
        res = self.decision(refresh_signals=signals)
        self.assertEqual(res["public"]["gate"], "HOLD_RUNTIME_UNVERIFIED")

    def test_missing_one_expected_live_name_holds_even_with_extra(self):
        args = scenario()
        args["live_names"].remove("synthetic_57")
        res = plan_dry_run(**args)
        self.assertEqual(res["public"]["decision"], "HOLD_MISSING_LIVE_NAMES")
        self.assertEqual(res["public"]["present_names"], 57)

    def test_unknown_full_source_coverage_and_non_ai_diff_are_vetoes(self):
        self.assertEqual(self.decision(coverage_verified=False)["public"]["decision"],
                         "HOLD_SOURCE_COVERAGE")
        signals = successful_refresh()
        signals["non_ai_changes"] = 1
        self.assertEqual(self.decision(refresh_signals=signals)["public"]["gate"],
                         "HOLD_NON_AI_INVARIANT_BREACH")

    def test_network_candidate_or_homepage_http_is_not_business_evidence(self):
        args = scenario()
        for entry in args["previous_state"].values():
            entry["services"]["chatgpt"]["status"] = "NETWORK_CANDIDATE"
            entry["services"]["chatgpt"]["method"] = "homepage_http_200"
        res = plan_dry_run(**args)
        self.assertEqual(res["public"]["qualified_candidates"], 0)
        self.assertEqual(res["public"]["decision"], "NO_BUSINESS_VERIFIED_BACKUP")

    def test_shared_ai_parent_requires_all_three_business_proofs(self):
        args = scenario()
        args["service"] = "shared_all_services"
        self.assertEqual(plan_dry_run(**args)["public"]["decision"], "DRY_RUN_SWITCH_CANDIDATE")
        args["previous_state"]["synthetic_01"]["services"]["notebooklm"]["checks"]["source_imported"] = False
        result = plan_dry_run(**args)
        self.assertEqual(result["public"]["qualified_candidates"], 1)
        self.assertEqual(result["public"]["decision"], "NO_BUSINESS_VERIFIED_BACKUP")
        self.assertIsNone(result["private_target"])

    def test_changed_manifest_under_no_change_event_is_not_trusted(self):
        args = scenario()
        new_nodes = dict(args["current_manifest"]["node_fingerprints"])
        new_nodes["synthetic_01"] = "b"*64
        args["current_manifest"] = manifest(new_nodes)
        self.assertEqual(plan_dry_run(**args)["public"]["decision"],
                         "HOLD_MANIFEST_EVENT_INCONSISTENT")

    def test_unknown_current_health_string_fails_closed(self):
        with self.assertRaises(ValueError):
            self.decision(current_healthy="UNKNOWN")
        with self.assertRaises(ValueError):
            self.decision(global_incident="false")

    def test_notebooklm_import_and_qa_are_mandatory(self):
        args = scenario()
        args["service"] = "notebooklm"
        args["previous_state"]["synthetic_01"]["services"]["notebooklm"]["checks"]["source_imported"] = False
        result = plan_dry_run(**args)
        self.assertEqual(result["public"]["qualified_candidates"], 1)
        self.assertEqual(result["public"]["decision"], "NO_BUSINESS_VERIFIED_BACKUP")

    def test_service_independence_google_login_does_not_verify_notebooklm(self):
        args = scenario()
        args["service"] = "notebooklm"
        for st in args["previous_state"].values():
            st["services"]["notebooklm"]["status"] = "NETWORK_CANDIDATE"
        self.assertEqual(plan_dry_run(**args)["public"]["qualified_candidates"], 0)

    def test_stale_geography_or_health_does_not_qualify(self):
        args = scenario()
        args["observations"]["synthetic_01"]["health"]["observed_at"] = ts(-60)
        self.assertEqual(plan_dry_run(**args)["public"]["qualified_candidates"], 1)
        args["observations"]["synthetic_00"]["egress"]["verified"] = False
        self.assertEqual(plan_dry_run(**args)["public"]["qualified_candidates"], 0)

    def test_changed_same_name_fingerprint_invalidates_old_business_proof(self):
        args = scenario()
        new_nodes = dict(args["current_manifest"]["node_fingerprints"])
        new_nodes["synthetic_01"] = "b"*64
        args["current_manifest"] = manifest(new_nodes)
        args["refresh_signals"]["update_event"] = "UPDATED"
        args["refresh_signals"]["source_changed"] = True
        res = plan_dry_run(**args)
        self.assertEqual(res["public"]["qualified_candidates"], 1)
        self.assertEqual(res["public"]["decision"], "NO_BUSINESS_VERIFIED_BACKUP")
        self.assertIn("synthetic_01", res["private_probe_queue"])

    def test_healthy_sticks_to_current_even_if_backup_is_faster(self):
        args = scenario()
        args["observations"]["synthetic_01"]["health"]["rtt_p95_ms"] = 20
        args["current_healthy"] = True
        self.assertEqual(plan_dry_run(**args)["public"]["decision"], "HOLD_HEALTHY_STICKY")

    def test_manual_parent_group_protected(self):
        self.assertEqual(self.decision(mode="MANUAL")["public"]["decision"], "HOLD_MANUAL")
        self.assertEqual(self.decision(ai_parent_selected_stable=False)["public"]["decision"],
                         "HOLD_MANUAL")

    def test_single_failure_or_single_target_does_not_trigger_switch(self):
        args = scenario()
        args["failure_events"] = args["failure_events"][:1]
        self.assertEqual(plan_dry_run(**args)["public"]["decision"], "HOLD_INSUFFICIENT_NODE_EVIDENCE")
        args = scenario()
        for event in args["failure_events"]:
            event["target"] = "http"
        self.assertEqual(plan_dry_run(**args)["public"]["decision"], "HOLD_INSUFFICIENT_NODE_EVIDENCE")

    def test_403_429_5xx_are_not_node_network_evidence(self):
        for failure_kind in ("quota_429", "geo_403", "platform_5xx"):
            args = scenario()
            for event in args["failure_events"]:
                event["kind"] = failure_kind
            self.assertEqual(plan_dry_run(**args)["public"]["decision"],
                             "HOLD_INSUFFICIENT_NODE_EVIDENCE")
        self.assertEqual(self.decision(global_incident=True)["public"]["decision"],
                         "HOLD_SHARED_OR_UNKNOWN_OUTAGE")

    def test_cooldown_uninitialized_history_and_minimum_dwell(self):
        self.assertEqual(self.decision(state_history_ready=False)["public"]["decision"],
                         "HOLD_UNINITIALIZED_HISTORY")
        self.assertEqual(self.decision(selected_since=ts(-2))["public"]["decision"],
                         "HOLD_MINIMUM_DWELL")
        self.assertEqual(self.decision(selected_since=None)["public"]["decision"],
                         "HOLD_DWELL_UNVERIFIED")
        self.assertEqual(self.decision(cooldown_until=ts(20))["public"]["decision"],
                         "HOLD_COOLDOWN")
        self.assertEqual(self.decision(cooldown_until="bad")["public"]["decision"],
                         "HOLD_INVALID_COOLDOWN")

    def test_region_lock_never_crosses_country(self):
        args = scenario()
        args["observations"]["synthetic_01"]["egress"]["country"] = "JP"
        self.assertEqual(plan_dry_run(**args)["public"]["decision"],
                         "NO_BUSINESS_VERIFIED_BACKUP")
        args = scenario()
        args["observations"]["synthetic_00"]["egress"]["country"] = "HK"
        self.assertEqual(plan_dry_run(**args)["public"]["decision"],
                         "HOLD_CURRENT_REGION_UNVERIFIED")

    def test_stability_success_rate_outranks_raw_low_latency(self):
        args = scenario()
        third = "synthetic_02"
        fp = args["current_manifest"]["node_fingerprints"][third]
        args["previous_state"][third] = {
            "fingerprint": fp,
            "services": {svc: evidence(fp, svc) for svc in WORKFLOW_TASKS}
        }
        args["observations"][third] = record(fp, rate=0.96, rtt=10)
        result = plan_dry_run(**args)
        self.assertEqual(result["public"]["qualified_candidates"], 3)
        self.assertEqual(result["private_target"], "synthetic_01")

    def test_stale_or_single_source_current_region_cannot_switch(self):
        args = scenario()
        args["observations"]["synthetic_00"]["egress"]["observed_at"] = ts(-1600)
        self.assertEqual(plan_dry_run(**args)["public"]["decision"],
                         "HOLD_CURRENT_REGION_UNVERIFIED")
        args = scenario()
        args["observations"]["synthetic_00"]["egress"]["independent_sources"] = 1
        self.assertEqual(plan_dry_run(**args)["public"]["decision"],
                         "HOLD_CURRENT_REGION_UNVERIFIED")

    def test_all_three_business_workflows_cannot_be_inferred_from_http_200(self):
        args = scenario()
        args["service"] = "shared_all_services"
        for row in args["previous_state"].values():
            row["services"]["notebooklm"]["method"] = "homepage_http_200"
        result = plan_dry_run(**args)
        self.assertEqual(result["public"]["qualified_candidates"], 0)
        self.assertIsNone(result["private_target"])

    def test_active_pools_without_business_verified_backup_never_switch(self):
        args = scenario()
        args["previous_state"]["synthetic_01"]["services"]["chatgpt"]["expires_at"] = ts(-10)
        self.assertEqual(plan_dry_run(**args)["public"]["decision"],
                         "NO_BUSINESS_VERIFIED_BACKUP")

    def test_private_node_identifiers_are_absent_from_public_report(self):
        res = self.decision()
        report = repr(res["public"])
        for private in ("synthetic_00", "synthetic_01", "unverified_extra_leaf"):
            self.assertNotIn(private, report)
        self.assertTrue(res["private_target"].startswith("synthetic_"))

    def test_unverified_invalid_input_and_naive_clock_fail_closed(self):
        with self.assertRaises(ValueError):
            self.decision(now=datetime(2026, 11, 14))
        with self.assertRaises(ValueError):
            self.decision(service="unverified_product")
        with self.assertRaises(ValueError):
            self.decision(coverage_verified=1)


if __name__ == "__main__":
    unittest.main()
