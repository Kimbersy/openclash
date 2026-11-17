"""The daily OpenClash schedule alone is never a verified refresh event."""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_refresh_transition_gate import decide_refresh


def baseline(**overrides):
    args = {
        "update_event": "UPDATED",
        "source_changed": True,
        "source_runtime_disk_equal": True,
        "live_api_reachable": True,
        "live_membership_matches": True,
        "full_runtime_reload_confirmed": True,
        "stable_snapshot_samples": 2,
        "non_ai_changes": 0,
    }
    args.update(overrides)
    return decide_refresh(**args)


class AiRefreshTransitionTests(unittest.TestCase):
    def test_qualified_update_only_plans_reconciliation_not_live_switch(self):
        report = baseline()
        self.assertEqual(report["decision"], "PLAN_INCREMENTAL_AI_ONLY")
        self.assertTrue(report["plan_reconciliation"])
        self.assertFalse(report["ai_catalog_apply"])
        self.assertTrue(report["preserve_non_ai"])

    def test_daily_schedule_and_disk_match_not_enough(self):
        # Exactly what user's 2026-11-13 router receipt verifies.
        report = baseline(
            update_event="UNKNOWN",
            source_changed=False,
            live_api_reachable=False,
            live_membership_matches=False,
            full_runtime_reload_confirmed=False,
            stable_snapshot_samples=1,
        )
        self.assertEqual(report["decision"], "HOLD_UPDATE_UNCONFIRMED")

    def test_failed_refresh_cannot_invalidate_stable_pool(self):
        self.assertEqual(baseline(update_event="ERROR")["decision"], "HOLD_REMOTE_ERROR")

    def test_disk_source_and_runtime_mismatch_blocks(self):
        self.assertEqual(baseline(source_runtime_disk_equal=False)["decision"], "HOLD_DISK_MISMATCH")

    def test_runtime_api_unavailable_blocks(self):
        self.assertEqual(baseline(live_api_reachable=False)["decision"], "HOLD_RUNTIME_UNVERIFIED")

    def test_same_names_in_api_without_full_reload_attestation_blocks(self):
        self.assertEqual(
            baseline(full_runtime_reload_confirmed=False)["decision"],
            "HOLD_RUNTIME_UNVERIFIED",
        )

    def test_membership_mismatch_even_when_reload_attested_blocks(self):
        self.assertEqual(
            baseline(live_membership_matches=False)["decision"],
            "HOLD_RUNTIME_UNVERIFIED",
        )

    def test_stable_samples_needed(self):
        self.assertEqual(
            baseline(stable_snapshot_samples=1)["decision"], "HOLD_UNSTABLE_SNAPSHOT"
        )

    def test_refresh_no_change_preserves_current_pool(self):
        report = baseline(update_event="NO_CHANGE", source_changed=False)
        self.assertEqual(report["decision"], "KEEP_CURRENT_AI_CATALOG")
        self.assertFalse(report["plan_reconciliation"])

    def test_event_and_source_hash_disagreement_blocks(self):
        for event, changed in (("UPDATED", False), ("NO_CHANGE", True)):
            with self.subTest(event=event):
                self.assertEqual(
                    baseline(update_event=event, source_changed=changed)["decision"],
                    "HOLD_EVENT_SOURCE_INCONSISTENT",
                )

    def test_non_ai_diff_is_strict_veto(self):
        report = baseline(non_ai_changes=1)
        self.assertEqual(report["decision"], "HOLD_NON_AI_INVARIANT_BREACH")
        self.assertFalse(report["ai_catalog_apply"])
        self.assertFalse(report.get("plan_reconciliation", False))

    def test_rejects_malformed_signals(self):
        with self.assertRaises(ValueError):
            baseline(update_event="log said success")
        with self.assertRaises(ValueError):
            baseline(stable_snapshot_samples=True)
        with self.assertRaises(ValueError):
            baseline(source_changed=1)
        with self.assertRaises(ValueError):
            baseline(non_ai_changes=-1)


if __name__ == "__main__":
    unittest.main()
