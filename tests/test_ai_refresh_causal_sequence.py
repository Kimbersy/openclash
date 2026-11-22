"""Synthetic natural-refresh clock / postcommit cause-before-effect tests."""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from ai_refresh_causal_sequence import assess_natural_refresh

BOOT = "6ad25c00-1122-3344-5566-778899aabbcc"
SOURCE = "a" * 64
RUNTIME = "b" * 64


def fixture():
    return dict(
        update={"source": "instrumented_openclash_postcommit",
                "verified_download": True, "validated_write": True,
                "atomic_commit_verified": True,
                "latest_event": "VALIDATED_CHANGED", "run_id": "natural-20261114-001",
                "source_sha256": SOURCE, "boot_id": BOOT, "commit_ticks": 120_000},
        core={"boot_id": BOOT, "only_production_core": True,
              "executable_verified": True, "source_run_id": "natural-20261114-001",
              "start_ticks": 121_000, "checked_ticks": 123_000,
              "config_unchanged_during_start": True,
              "runtime_file_sha256": RUNTIME},
        api={"boot_id": BOOT, "core_identity_matches": True,
             "socket_owned_by_production_pid": True, "authenticated_get": True,
             "expected_disk_names_present": True, "two_stable_reads": True,
             "core_run_id": "natural-20261114-001", "read_ticks": 123_500},
        current_boot_id=BOOT, hz_from_kernel_auxv=100,
        sample_now_ticks=125_000, source_snapshot_sha256=SOURCE,
        runtime_render_sha256=RUNTIME, source_coverage_verified=True,
        non_ai_changes=0,
    )


def check(**patch):
    data = fixture()
    data.update(patch)
    return assess_natural_refresh(**data)


class RefreshCausalSequenceTests(unittest.TestCase):
    def test_even_simulated_cold_start_never_proves_connection_secrets(self):
        result = check()
        self.assertEqual(result["stage"], "COLD_START_CHRONOLOGY_CANDIDATE_ONLY")
        self.assertTrue(result["cold_start_candidate"])
        self.assertFalse(result["runtime_identity_proven"])
        self.assertFalse(result["allow_reconcile"])
        self.assertFalse(result["allow_switch"])
        self.assertFalse(result["writes"])

    def test_actual_2352_names_and_missing_getconf_do_not_unlock(self):
        value = check(update=None, core=None, api={"expected_disk_names_present": True},
                      hz_from_kernel_auxv=None)
        self.assertEqual(value["stage"], "HOLD_NO_POSTCOMMIT_OBSERVER")

    def test_log_or_ui_success_not_real_postcommit_receipt(self):
        base = fixture()["update"]
        for change in ({"source": "openclash_log"},
                       {"source": "ui_update_started"},
                       {"verified_download": False},
                       {"atomic_commit_verified": False},
                       {"latest_event": "NO_CHANGE"},
                       {"latest_event": "FAILED"},
                       {"validated_write": False}):
            with self.subTest(change=change):
                self.assertEqual(check(update=base | change)["stage"],
                                 "HOLD_UPDATE_COMMIT_UNVERIFIED")

    def test_half_write_digest_replacement_and_stale_file(self):
        self.assertEqual(check(update=fixture()["update"] | {"source_sha256": "f" * 64})["stage"],
                         "HOLD_SOURCE_HASH_MISMATCH")
        self.assertEqual(check(core=fixture()["core"] | {"config_unchanged_during_start": False})["stage"],
                         "HOLD_RUNTIME_FILE_CONCURRENT_CHANGE")
        self.assertEqual(check(core=fixture()["core"] | {"runtime_file_sha256": "f" * 64})["stage"],
                         "HOLD_RUNTIME_FILE_MISMATCH")

    def test_core_predates_update_and_no_atomic_sequence(self):
        core = fixture()["core"]
        self.assertEqual(check(core=core | {"start_ticks": 119_999})["stage"],
                         "HOLD_CORE_NOT_STARTED_AFTER_COMMIT")
        self.assertEqual(check(core=core | {"checked_ticks": 120_500})["stage"],
                         "HOLD_CORE_NOT_STARTED_AFTER_COMMIT")
        self.assertEqual(check(update=fixture()["update"] | {"commit_ticks": 126_000})["stage"],
                         "HOLD_COMMIT_CLOCK_INVALID")

    def test_reboot_and_unknown_clock_fail_closed(self):
        self.assertEqual(check(core=fixture()["core"] | {"boot_id": "f" * 64})["stage"],
                         "HOLD_CORE_BOOT_OR_RECORD")
        self.assertEqual(check(update=fixture()["update"] | {"boot_id": "f" * 64})["stage"],
                         "HOLD_BOOT_CHANGED")
        self.assertEqual(check(hz_from_kernel_auxv=None)["stage"], "HOLD_KERNEL_CLOCK_UNVERIFIED")
        self.assertEqual(check(hz_from_kernel_auxv=True)["stage"], "HOLD_KERNEL_CLOCK_UNVERIFIED")
        self.assertEqual(check(sample_now_ticks=0)["stage"], "HOLD_COMMIT_CLOCK_INVALID")

    def test_stale_event_unrelated_run_and_multiple_cores(self):
        self.assertEqual(check(sample_now_ticks=600_001)["stage"], "HOLD_COMMIT_TOO_OLD")
        self.assertEqual(check(core=fixture()["core"] | {"source_run_id": "unrelated"})["stage"],
                         "HOLD_CORE_PROVENANCE")
        self.assertEqual(check(api=fixture()["api"] | {"core_run_id": "unrelated"})["stage"],
                         "HOLD_RUNTIME_GENERATION_MISMATCH")
        self.assertEqual(check(core=fixture()["core"] | {"only_production_core": False})["stage"],
                         "HOLD_CORE_PROVENANCE")

    def test_authenticated_api_names_are_not_full_connection_identity(self):
        api = fixture()["api"]
        self.assertEqual(check(api=api | {"two_stable_reads": False})["stage"],
                         "HOLD_RUNTIME_API_UNVERIFIED")
        self.assertEqual(check(api=api | {"authenticated_get": False})["stage"],
                         "HOLD_RUNTIME_API_UNVERIFIED")
        self.assertEqual(check(api=api | {"read_ticks": 122_999})["stage"],
                         "HOLD_RUNTIME_API_CLOCK_INVALID")

    def test_source_non_ai_invariants_and_anonymous_public_output(self):
        self.assertEqual(check(non_ai_changes=1)["stage"], "HOLD_NON_AI_INVARIANT")
        self.assertEqual(check(source_coverage_verified=False)["stage"], "HOLD_SOURCE_COVERAGE")
        result = check()
        for secret in ("natural-20261114-001", SOURCE, RUNTIME, BOOT):
            self.assertNotIn(secret, repr(result))


if __name__ == "__main__":
    unittest.main()
