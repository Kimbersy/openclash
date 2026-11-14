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
    KNOWN_UPSTREAM_BLOB_SHA, KNOWN_DEVICE_UPDATER_BLOB_SHA,
    KNOWN_DEVICE_UPDATER_COMMIT, audit_installed_device_updater,
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



# Synthetic representation of version-specific Aug 2026 branch control flow.
# The real fixed Git object is verified by GitHub, not mirrored in this test.
FAKE_DEVICE_SOURCE = b"""#!/bin/bash
# synthetic updater; never run or install this fixture on a router
config_su_check()
{
  cmp -s "$CONFIG_FILE" "$CFG_FILE"
  if [ "$?" -ne 0 ]; then
    mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null
    LOG_OUT "Config File\xe3\x80\x90$name\xe3\x80\x91Update Successful!"
  else
    LOG_OUT "Config File\xe3\x80\x90$name\xe3\x80\x91No Change, Do Nothing!"
    return
  fi
  mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null
  LOG_OUT "Config File\xe3\x80\x90$name\xe3\x80\x91Update Successful!"
  if [ "$CONFIG_FILE" == "$CONFIG_PATH" ]; then
    restart=1
  fi
}
config_error()
{
  LOG_ERROR "Update Error"
  rm -rf "$CFG_FILE"
}
change_dns()
{
  :
}
dec_job_counter_and_restart "$restart"
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
    def test_real_router_script_matches_official_august_2026_file_pin_not_package_version(self):
        self.assertEqual(KNOWN_DEVICE_UPDATER_BLOB_SHA,
                         "ac6640de36be1cf7dc11ae73796a89078269542c")
        self.assertEqual(KNOWN_DEVICE_UPDATER_COMMIT,
                         "813a60a21fba2ec34c3a42f7fdc3d71b47694d25")
        self.assertNotEqual(KNOWN_DEVICE_UPDATER_BLOB_SHA, KNOWN_UPSTREAM_BLOB_SHA)
        self.assertEqual(audit_installed_device_updater(FAKE_DEVICE_SOURCE)["status"],
                         "HOLD_DEVICE_VERSION_DRIFT")

    def test_aug_2026_two_unchecked_moves_and_missing_exit_code_are_detected(self):
        fixture_sha = git_blob_sha1(FAKE_DEVICE_SOURCE)
        result = audit_installed_device_updater(FAKE_DEVICE_SOURCE,
                                                fixture_blob_sha=fixture_sha)
        self.assertEqual(result["status"], "KNOWN_DEVICE_AUG2026_UNCHECKED_MOVE")
        self.assertEqual(result["unchecked_move_branches"], 2)
        self.assertEqual(result["unchecked_success_messages"], 2)
        self.assertFalse(result["script_returns_explicit_exit_code"])
        self.assertFalse(result["explicit_error_exit_state"])
        self.assertFalse(result["real_device_pin"])
        self.assertFalse(result["can_instrument"])
        self.assertFalse(result["allow_switch"])

    def test_aug_2026_old_version_guard_blocks_unexpected_hotfix_or_october_script(self):
        altered = FAKE_DEVICE_SOURCE.replace(b"  restart=1", b"  restart=0")
        self.assertEqual(audit_installed_device_updater(
            altered, fixture_blob_sha=git_blob_sha1(altered))["status"],
            "HOLD_UNEXPECTED_SCRIPT_STRUCTURE")
        altered = FAKE_DEVICE_SOURCE + b'\nexit "$exit_code"\n'
        self.assertEqual(audit_installed_device_updater(
            altered, fixture_blob_sha=git_blob_sha1(altered))["status"],
            "HOLD_UNEXPECTED_SCRIPT_STRUCTURE")
        altered = FAKE_DEVICE_SOURCE.replace(b'rm -rf "$CFG_FILE"',
                                             b'exit_code=1\n  rm -rf "$CFG_FILE"')
        self.assertEqual(audit_installed_device_updater(
            altered, fixture_blob_sha=git_blob_sha1(altered))["status"],
            "HOLD_UNEXPECTED_SCRIPT_STRUCTURE")

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
