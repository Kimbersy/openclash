"""No external service: prove subscription-to-live-core gates fail closed."""
import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_refresh_event_gate import assess, catalog_digest

NOW = datetime(2026,11,13,12,50,tzinfo=timezone.utc)
MANIFEST = {
    "schema_version":1,
    "generated_at": NOW.isoformat(),
    "subscription_snapshot":{"sha256":"a"*64,"byte_count":120},
    "node_count":1,"node_fingerprints":{"PRIVATE-NODE":"b"*64},
}
UPDATE = {"source":"verified_openclash_commit_observer",
          "result":"VALIDATED_CHANGED","validated_download":True,
          "committed":True,"run_id":"openclash-sub-001",
          "finished_at":(NOW - timedelta(minutes=2)).isoformat(),
          "snapshot_sha256":"a"*64}
RUNTIME = {"source":"authenticated_live_mihomo_snapshot",
           "core_running":True,"authenticated":True,
           "all_providers_loaded":True,"run_id":"openclash-sub-001",
           "observed_at":(NOW - timedelta(minutes=1)).isoformat(),
           "live_node_identity_digest":catalog_digest(MANIFEST)}


def gate(m=MANIFEST,u=UPDATE,v=RUNTIME,coverage=True):
    return assess(m,u,v,source_coverage_verified=coverage,now=NOW)


class TestAiRefreshGate(unittest.TestCase):
    def test_fully_confirmed_is_still_read_only(self):
        value=gate()
        self.assertEqual(value["status"],"VERIFIED_SNAPSHOT_READY")
        self.assertTrue(value["allow_reconcile"])
        self.assertFalse(value["allow_switch"])

    def test_no_change_requires_real_validation_not_log_substring(self):
        ok=gate(u=UPDATE | {"result":"VALIDATED_NO_CHANGE"})
        self.assertTrue(ok["allow_reconcile"])
        for bad in [
            {"source":"ui_update_clicked","result":"VALIDATED_NO_CHANGE"},
            {"result":"NO_CHANGE"},
            {"result":"VALIDATED_NO_CHANGE","validated_download":False},
            {"result":"VALIDATED_NO_CHANGE","committed":False},
        ]:
            result=gate(u=UPDATE | bad)
            self.assertEqual(result["status"],"HOLD_NO_REFRESH_PROOF")
            self.assertFalse(result["allow_reconcile"])

    def test_missing_data_never_claims_refresh(self):
        self.assertEqual(gate(u=None)["reason"],"MISSING_UPDATE_EVENT")
        self.assertEqual(gate(v=None)["reason"],"MISSING_RUNTIME_EVIDENCE")
        self.assertEqual(gate(coverage=False)["reason"],"INCOMPLETE_SOURCE_COVERAGE")
        self.assertEqual(gate(m={})["reason"],"BAD_MANIFEST")
        self.assertEqual(gate(m=MANIFEST | {"node_count":2})["reason"],"BAD_MANIFEST")

    def test_disk_equals_disk_cannot_act_as_live_reload(self):
        observed=RUNTIME | {"source":"on_disk_yaml_equality"}
        self.assertEqual(gate(v=observed)["reason"],"RUNTIME_NOT_PROVEN")
        self.assertEqual(gate(v=RUNTIME | {"authenticated":False})["reason"],"RUNTIME_NOT_PROVEN")

    def test_wrong_refresh_or_core_generation_blocked(self):
        self.assertEqual(gate(v=RUNTIME | {"run_id":"openclash-sub-000"})["reason"],"RUNTIME_NOT_PROVEN")
        self.assertEqual(gate(v=RUNTIME | {"core_running":False})["reason"],"RUNTIME_NOT_PROVEN")
        self.assertEqual(gate(v=RUNTIME | {"all_providers_loaded":False})["reason"],"RUNTIME_NOT_PROVEN")

    def test_stale_and_future_update_cannot_be_used(self):
        for time in [NOW - timedelta(days=2), NOW + timedelta(seconds=1)]:
            self.assertEqual(gate(u=UPDATE | {"finished_at":time.isoformat()})["reason"],"STALE_UPDATE_EVENT")

    def test_core_evidence_must_follow_finished_update(self):
        earlier=UPDATE["finished_at"]
        self.assertEqual(
            gate(v=RUNTIME | {"observed_at":(NOW - timedelta(minutes=3)).isoformat()})["reason"],
            "RUNTIME_EVIDENCE_STALE_OR_PREUPDATE")
        self.assertEqual(
            gate(v=RUNTIME | {"observed_at":(NOW + timedelta(seconds=30)).isoformat()})["reason"],
            "RUNTIME_EVIDENCE_STALE_OR_PREUPDATE")

    def test_identity_mismatch_blocks(self):
        self.assertEqual(gate(u=UPDATE | {"snapshot_sha256":"c"*64})["reason"],"UPDATE_SNAPSHOT_MISMATCH")
        self.assertEqual(gate(v=RUNTIME | {"live_node_identity_digest":"c"*64})["reason"],"LIVE_NODE_IDENTITY_MISMATCH")

    def test_running_yaml_metadata_can_differ_but_full_connection_identity_must_match(self):
        changed_source = MANIFEST | {"subscription_snapshot": {"sha256":"c"*64,"byte_count":127}}
        updated=UPDATE | {"snapshot_sha256":"c"*64}
        # OpenClash may regenerate runtime YAML metadata, without changing
        # the proxies. Accept only the canonical node map identity, not disk bytes.
        self.assertEqual(gate(m=changed_source,u=updated)["status"],"VERIFIED_SNAPSHOT_READY")
        changed_node=MANIFEST | {"node_fingerprints":{"PRIVATE-NODE":"f"*64}}
        self.assertEqual(gate(m=changed_node)["reason"],"LIVE_NODE_IDENTITY_MISMATCH")

    def test_outputs_do_not_contain_sensitive_identifiers(self):
        for result in [gate(),gate(u=UPDATE | {"snapshot_sha256":"SECRET PRIVATE URL"})]:
            self.assertNotIn("PRIVATE-NODE",repr(result))
            self.assertNotIn("SECRET",repr(result))
            self.assertNotIn("a"*64,repr(result))
        self.assertNotIn("PRIVATE-NODE",repr(gate(m=MANIFEST | {"node_count":2})))

    def test_bad_timestamps_and_invalid_parameters(self):
        self.assertEqual(gate(u=UPDATE | {"finished_at":"2026-11-13 13:00"})["reason"],"STALE_UPDATE_EVENT")
        self.assertEqual(gate(v=RUNTIME | {"observed_at":""})["reason"],"RUNTIME_EVIDENCE_STALE_OR_PREUPDATE")
        with self.assertRaises(ValueError):
            assess(MANIFEST,UPDATE,RUNTIME,source_coverage_verified=True,now=NOW,max_age_seconds=1)


if __name__=="__main__":
    unittest.main()
