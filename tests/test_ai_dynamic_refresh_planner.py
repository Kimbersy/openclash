"""No live networking: protect dynamic daily updates from stale AI qualifications."""
import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_dynamic_refresh_planner import updated_state

NOW = datetime(2026, 11, 13, 12, tzinfo=timezone.utc)
NEXT = (NOW + timedelta(days=2)).isoformat()
PAST = (NOW - timedelta(days=1)).isoformat()


def manifest(nodes, digest="a"):
    return {
        "schema_version": 1,
        "generated_at": NOW.isoformat(),
        "subscription_snapshot": {"sha256": digest*64, "byte_count": 250},
        "node_count": len(nodes),
        "node_fingerprints": dict(nodes),
    }


def evidence(name, fp, expiry=NEXT, statuses=None):
    statuses = statuses or {"chatgpt": "BUSINESS_VERIFIED",
                            "gemini": "NETWORK_CANDIDATE",
                            "notebooklm": "BUSINESS_VERIFIED"}
    return {name: {"fingerprint": fp,
                   "services": {svc: {"status": status, "fingerprint": fp, "expires_at": expiry}
                                for svc, status in statuses.items()}}}


class DynamicRefreshPlannerTests(unittest.TestCase):
    def test_first_load_has_no_qualifications_and_queues_new_nodes(self):
        m = manifest({"A": "a"*64, "B": "b"*64})
        state, metrics, queue = updated_state(None, m, {}, update_succeeded=True, runtime_loaded=True, now=NOW)
        self.assertEqual(metrics["added"], 2)
        self.assertEqual(metrics["service_evidence_retained"], 0)
        self.assertEqual(metrics["service_evidence_reset"], 6)
        self.assertEqual(queue, ["A", "B"])
        self.assertEqual(state["A"]["services"]["notebooklm"]["status"], "UNKNOWN")

    def test_unchanged_identity_keeps_valid_business_proof_even_if_raw_format_changes(self):
        old = manifest({"A": "a"*64}, "a")
        new = manifest({"A": "a"*64}, "b")
        state, metrics, queue = updated_state(old, new, evidence("A", "a"*64),
                                               update_succeeded=True, runtime_loaded=True, now=NOW)
        self.assertEqual(queue, [])
        self.assertTrue(metrics["raw_snapshot_changed"])
        self.assertEqual(metrics["service_evidence_retained"], 3)
        self.assertEqual(metrics["nodes_queued_for_recheck"], 0)
        self.assertEqual(state["A"]["services"]["notebooklm"]["status"], "BUSINESS_VERIFIED")

    def test_same_named_route_change_resets_all_verdicts(self):
        old = manifest({"TW01": "a"*64})
        new = manifest({"TW01": "b"*64}, "b")
        state, metrics, queue = updated_state(old, new, evidence("TW01", "a"*64),
                                               update_succeeded=True, runtime_loaded=True, now=NOW)
        self.assertEqual(metrics["replaced_same_name"], 1)
        self.assertEqual(queue, ["TW01"])
        self.assertEqual([x["status"] for x in state["TW01"]["services"].values()], ["UNKNOWN"]*3)

    def test_added_removed_are_separate_and_kept_node_not_rechecked(self):
        old = manifest({"A": "a"*64, "B": "b"*64})
        new = manifest({"A": "a"*64, "C": "c"*64}, "b")
        state, metrics, queue = updated_state(old, new, evidence("A", "a"*64), update_succeeded=True,
                                               runtime_loaded=True, now=NOW)
        self.assertEqual((metrics["added"], metrics["removed"]), (1, 1))
        self.assertEqual(queue, ["C"])
        self.assertNotIn("B", state)

    def test_expired_node_service_is_unknown_while_others_retained(self):
        old = new = manifest({"A": "a"*64})
        past = evidence("A", "a"*64, expiry=PAST)
        past["A"]["services"]["chatgpt"]["expires_at"] = NEXT
        state, metrics, queue = updated_state(old, new, past, update_succeeded=True,
                                               runtime_loaded=True, now=NOW)
        self.assertEqual(state["A"]["services"]["chatgpt"]["status"], "BUSINESS_VERIFIED")
        self.assertEqual(state["A"]["services"]["notebooklm"]["status"], "UNKNOWN")
        self.assertEqual(metrics["service_evidence_expired"], 2)
        self.assertEqual(queue, ["A"])

    def test_partial_web_200_cannot_be_inherited_as_business_verified(self):
        old = new = manifest({"A": "a"*64})
        state, metrics, _ = updated_state(old, new,
             evidence("A", "a"*64, statuses={"notebooklm": "NETWORK_CANDIDATE"}),
             update_succeeded=True, runtime_loaded=True, now=NOW)
        self.assertEqual(state["A"]["services"]["notebooklm"]["status"], "NETWORK_CANDIDATE")
        self.assertNotEqual(state["A"]["services"]["notebooklm"]["status"], "BUSINESS_VERIFIED")
        self.assertEqual(metrics["service_evidence_retained"], 1)

    def test_update_failure_and_unloaded_core_both_fail_closed(self):
        old = new = manifest({"A": "a"*64})
        for success, loaded in ((False, True), (True, False), (False, False)):
            with self.assertRaisesRegex(ValueError, "not confirmed loaded"):
                updated_state(old, new, evidence("A", "a"*64),
                              update_succeeded=success, runtime_loaded=loaded, now=NOW)

    def test_node_count_is_not_a_stable_identity(self):
        old = manifest({"A": "a"*64, "B": "b"*64})
        new = manifest({"A": "b"*64, "B": "a"*64}, "b")
        state, metrics, queue = updated_state(old, new, evidence("A", "a"*64),
                                              update_succeeded=True, runtime_loaded=True, now=NOW)
        self.assertEqual(metrics["current"], 2)
        self.assertEqual(metrics["replaced_same_name"], 2)
        self.assertEqual(queue, ["A", "B"])
        self.assertEqual(state["A"]["services"]["notebooklm"]["status"], "UNKNOWN")

    def test_missing_or_bad_private_manifest_is_rejected(self):
        new = manifest({"A": "a"*64})
        with self.assertRaises(ValueError):
            updated_state({"node_count": 1}, new, {}, update_succeeded=True,
                          runtime_loaded=True, now=NOW)
        with self.assertRaises(ValueError):
            updated_state(None, new, None, update_succeeded=True,
                          runtime_loaded=True, now=NOW)

    def test_never_expose_raw_credentials_in_summary(self):
        name = "private-user-node"
        old = new = manifest({name: "a"*64})
        state, metrics, queue = updated_state(old, new, evidence(name,"a"*64),
                                              update_succeeded=True, runtime_loaded=True, now=NOW)
        self.assertNotIn(name, repr(metrics))
        self.assertIn(name, queue) if queue else self.assertEqual(queue, [])
        self.assertIn(name, state)  # state & queue are PRIVATE, never sent to GitHub/chat


if __name__ == "__main__":
    unittest.main()
