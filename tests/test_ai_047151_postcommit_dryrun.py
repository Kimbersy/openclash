"""Minimal synthetic failure injection; no private nodes or device operations."""
import copy
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from ai_047151_postcommit_dryrun import assess_transaction
from ai_openclash_updater_contract import KNOWN_DEVICE_UPDATER_BLOB_SHA

BOOT = "12345678-1234-1234-1234-123456789abc"
RUN = "scheduled-20261114-0001"


def trace():
    rows = [
        {"stage": "download", "tick": 100, "ok": True, "body_valid": True},
        {"stage": "yaml_validated", "tick": 101, "ok": True},
        {"stage": "move", "tick": 102, "exit_code": 0, "staged_sha256": "a" * 64},
        {"stage": "readback", "tick": 103, "ok": True, "committed_sha256": "a" * 64},
    ]
    for item in rows:
        item.update(run_id=RUN, boot_id=BOOT)
    return {
        "installed_updater_blob": KNOWN_DEVICE_UPDATER_BLOB_SHA,
        "locked": True, "rollback_backup": True, "interrupted": False,
        "rebooted": False, "rollback_started": False, "overlapping_run": False,
        "outcome": "CHANGED", "selected_active_source": True, "source_changed": True,
        "protected_hook": True, "run_id": RUN, "boot_id": BOOT, "events": rows,
    }


class Test047151PostcommitDryrun(unittest.TestCase):
    def check(self, modify):
        t = trace()
        modify(t)
        v = assess_transaction(t)
        self.assertFalse(v["allow_switch"])
        self.assertFalse(v["allow_reconcile"])
        self.assertFalse(v["runtime_identity_proven"])
        self.assertFalse(v["production_writes"])
        self.assertNotIn("scheduled-20261114", repr(v))
        self.assertNotIn("a" * 64, repr(v))
        return v

    def test_even_synthetic_complete_transaction_is_only_untrusted_candidate(self):
        v = self.check(lambda t: None)
        self.assertEqual(v["stage"], "LOCAL_POSTCOMMIT_CONTRACT_CANDIDATE_ONLY")
        self.assertTrue(v["local_commit_candidate"])

    def test_failed_download_conversion_move_and_postread(self):
        edits = (
            lambda t: t["events"][0].update(ok=False),
            lambda t: t["events"][0].update(body_valid=False),
            lambda t: t["events"][1].update(ok=False),
            lambda t: t["events"][2].update(exit_code=1),
            lambda t: t["events"][3].update(ok=False),
            lambda t: t["events"][3].update(committed_sha256="b" * 64),
        )
        for edit in edits:
            self.assertFalse(self.check(edit)["local_commit_candidate"])

    def test_no_change_and_failure_are_not_new_commits(self):
        self.assertEqual(self.check(lambda t: t.update(outcome="NO_CHANGE"))["stage"],
                         "UNCHANGED_NO_NEW_COMMIT")
        self.assertEqual(self.check(lambda t: t.update(outcome="ERROR"))["stage"],
                         "HOLD_UPDATE_FAILED_OR_UNKNOWN")

    def test_reboot_power_loss_overlap_and_rollback_are_holds(self):
        for field in ("interrupted", "rebooted", "overlapping_run", "rollback_started"):
            self.assertFalse(self.check(lambda t, key=field: t.update({key: True}))
                             ["local_commit_candidate"])

    def test_lock_backup_version_and_protected_hook_are_required(self):
        self.assertEqual(self.check(lambda t: t.update(installed_updater_blob="b"*40))
                         ["stage"], "HOLD_VERSION_DRIFT")
        for key in ("locked", "rollback_backup", "protected_hook"):
            self.assertFalse(self.check(lambda t, k=key: t.update({k: False}))
                             ["local_commit_candidate"])

    def test_order_and_boot_run_generation_must_remain_consistent(self):
        self.assertEqual(self.check(lambda t: t["events"].reverse())["stage"], "HOLD_STAGE_ORDER")
        self.assertEqual(self.check(lambda t: t["events"][1].update(boot_id="different"))
                         ["stage"], "HOLD_RUN_GENERATION_MISMATCH")
        self.assertFalse(self.check(lambda t: t["events"][3].update(tick=99))
                         ["local_commit_candidate"])

    def test_no_secret_or_live_effects_for_invalid_trace(self):
        v = assess_transaction(None)
        self.assertEqual(v["stage"], "HOLD_NO_TRANSACTION")
        self.assertFalse(v["allow_switch"])


if __name__ == "__main__":
    unittest.main()
