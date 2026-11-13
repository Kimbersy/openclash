"""Offline pinned upstream move-safety audit and postcommit candidate contract.

All source and receipt data here are synthetic; no router, actual
subscription, real credential, network or installed observer is involved.
"""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_openclash_updater_contract import (
    audit_updater, assess_postcommit_contract, git_blob_sha1,
    KNOWN_UPSTREAM_BLOB_SHA,
)

FAKE_SOURCE = b"""#!/bin/bash
# synthetic only; no node secrets
config_su_check()
{
  cmp -s "$CONFIG_FILE" "$CFG_FILE"
  if [ "$?" -ne 0 ]; then
    mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null
    LOG_OUT "Config File\xe3\x80\x90$name\xe3\x80\x91Update Successful!"
  else
    LOG_OUT "Config File\xe3\x80\x90$name\xe3\x80\x91No Change, Do Nothing!"
  fi
  mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null
  LOG_OUT "Config File\xe3\x80\x90$name\xe3\x80\x91Update Successful!"
  restart=1
}
config_error()
{
  exit_code=1
}
dec_job_counter_and_restart "$restart"
exit "$exit_code"
"""


def sample(**updates):
    values = {
        "device_updater_exactly_pinned": True,
        "protected_run_id": "private-run-0001",
        "boot_id": "12345678-1234-1234-1234-123456789abc",
        "download_exit_ok": True,
        "downloaded_body_validated": True,
        "transformed_yaml_validated": True,
        "commit_outcome": "CHANGED",
        "selected_active_source": True,
        "staged_sha256": "a" * 64,
        "committed_sha256": "a" * 64,
        "mv_exit_status": 0,
        "readback_completed": True,
        "source_config_was_changed": True,
        "marker_written_by_protected_hook": True,
        "lock_held": True,
        "rollback_backup_verified": True,
    }
    values.update(updates)
    return assess_postcommit_contract(**values)


class UpdaterPostcommitContractTests(unittest.TestCase):
    def test_real_upstream_pin_is_fixed_nonempty_and_not_a_runtime_attestation(self):
        self.assertEqual(KNOWN_UPSTREAM_BLOB_SHA,
                         "6c181265ca96c452660653d60ec552d58eccc12c")
        # The synthetic fixture is not the real pinned script; production path
        # MUST refuse to instrument or claim the router version is known.
        self.assertEqual(audit_updater(FAKE_SOURCE)["status"], "HOLD_UPSTREAM_VERSION_DRIFT")
        self.assertFalse(audit_updater(FAKE_SOURCE)["can_instrument"])

    def test_fixture_reproduces_two_unchecked_moves_but_not_installed_hook(self):
        result = audit_updater(FAKE_SOURCE, expected_blob_sha=git_blob_sha1(FAKE_SOURCE))
        self.assertEqual(result["status"], "KNOWN_UPSTREAM_UNCHECKED_MOVE")
        self.assertEqual(result["unchecked_move_branches"], 2)
        self.assertEqual(result["plain_success_messages"], 2)
        self.assertFalse(result["can_instrument"])
        self.assertFalse(result["device_version_verified"])
        self.assertFalse(result["rollback_verified"])

    def test_version_drift_missing_branch_and_unexpected_bytes_fail_closed(self):
        fixture_pin = git_blob_sha1(FAKE_SOURCE)
        self.assertEqual(audit_updater(FAKE_SOURCE + b"changed", expected_blob_sha=fixture_pin)["status"],
                         "HOLD_UPSTREAM_VERSION_DRIFT")
        self.assertEqual(audit_updater(b"tiny")["status"], "HOLD_SOURCE_INVALID")
        self.assertEqual(audit_updater(FAKE_SOURCE, expected_blob_sha="bad-pin")["status"],
                         "HOLD_PIN_INVALID")
        broken = FAKE_SOURCE.replace(b"restart=1", b"no-restart")
        self.assertEqual(audit_updater(broken, expected_blob_sha=git_blob_sha1(broken))["status"],
                         "HOLD_UNEXPECTED_SCRIPT_STRUCTURE")

    def test_even_all_green_synthetic_event_does_not_authorize_ai_reconcile(self):
        result = sample()
        self.assertEqual(result["reason"], "POSTCOMMIT_OBSERVER_CONTRACT_CANDIDATE_ONLY")
        self.assertTrue(result["postcommit_candidate"])
        self.assertFalse(result["trusted_installed_observer"])
        self.assertFalse(result["full_runtime_identity_proven"])
        self.assertFalse(result["allow_reconcile"])
        self.assertFalse(result["allow_switch"])
        self.assertFalse(result["production_writes"])

    def test_log_substring_or_wrong_version_never_proves_commit(self):
        for patch in (
            {"device_updater_exactly_pinned": False},
            {"device_updater_exactly_pinned": "verified"},
            {"marker_written_by_protected_hook": False},
            {"lock_held": False},
            {"rollback_backup_verified": False},
        ):
            with self.subTest(patch=patch):
                self.assertFalse(sample(**patch)["postcommit_candidate"])

    def test_download_and_final_yaml_are_independently_validated(self):
        for patch in (
            {"download_exit_ok": False},
            {"downloaded_body_validated": False},
            {"transformed_yaml_validated": False},
            {"selected_active_source": False},
            {"download_exit_ok": 0},
        ):
            with self.subTest(patch=patch):
                self.assertFalse(sample(**patch)["postcommit_candidate"])

    def test_unchecked_move_and_postmove_file_difference_hold(self):
        for patch in (
            {"mv_exit_status": 1},
            {"mv_exit_status": None},
            {"mv_exit_status": True},
            {"readback_completed": False},
            {"committed_sha256": "b" * 64},
            {"staged_sha256": None},
            {"committed_sha256": "SHA256 public private"},
        ):
            with self.subTest(patch=patch):
                self.assertFalse(sample(**patch)["postcommit_candidate"])

    def test_no_change_is_not_changed_and_needs_actual_download_validation(self):
        nochange = sample(commit_outcome="NO_CHANGE", source_config_was_changed=False)
        self.assertFalse(nochange["postcommit_candidate"])
        self.assertEqual(nochange["reason"], "HOLD_NO_NEW_COMMIT_SEPARATE_NO_CHANGE_PROOF")
        self.assertFalse(sample(commit_outcome="NO_CHANGE",
                                source_config_was_changed=True)["postcommit_candidate"])
        self.assertFalse(sample(commit_outcome="NO_CHANGE",
                                source_config_was_changed=False,
                                downloaded_body_validated=False)["postcommit_candidate"])
        self.assertFalse(sample(commit_outcome="ERROR")["postcommit_candidate"])

    def test_invalid_run_id_or_boot_id_fails_closed(self):
        for patch in (
            {"protected_run_id": None},
            {"protected_run_id": "secret id url"},
            {"boot_id": None},
            {"boot_id": "previous-boot-uuid"},
        ):
            with self.subTest(patch=patch):
                self.assertFalse(sample(**patch)["postcommit_candidate"])

    def test_no_sensitive_fields_ever_reach_anonymous_public_status(self):
        for result in (sample(), sample(committed_sha256="d" * 64),
                       sample(protected_run_id="private user secret")):
            output = repr(result)
            for forbidden in ("private-run-0001", "12345678-1234-1234-1234-123456789abc",
                              "a" * 64, "secret"):
                self.assertNotIn(forbidden, output)


if __name__ == "__main__":
    unittest.main()
