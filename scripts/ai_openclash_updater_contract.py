#!/usr/bin/env python3
"""Version-pinned upstream OpenClash updater audit and postcommit proof CONTRACT.

Import-only. No local files, subprocess, network, router, credential or config
mutation. Deliberately does not generate an auto-installable patch. The running
router's updater SHA is unknown; NO incoming claim can substitute for verifying
the installed script bytes before proposing any hook deployment.

This is a contract for future trusted instrumentation, not an event observer:
all synthetic result flags are UNTRUSTED until generated inside a verified,
protected installed updater and independently corroborated.
"""
from __future__ import annotations

from hashlib import sha1
import re
from typing import Any

# vernesong/OpenClash commit 588cec56111c6f54a1ae24a4b848afbecc1a2f7f
# exact Git blob SHA for luci-app-openclash/root/usr/share/openclash/openclash.sh
KNOWN_UPSTREAM_BLOB_SHA = "6c181265ca96c452660653d60ec552d58eccc12c"

_HEX256 = re.compile(r"[0-9a-f]{64}\Z")
_UUID = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\Z")
_RUN = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9._:-]{3,127}\Z")

# Full upstream source is NOT bundled or redistributed in this repository.
# The audited copy is fetched from the pinned upstream Git commit by a maintainer.
EXPECTED_PLAIN_MV = 'mv "$CFG_FILE" "$CONFIG_FILE" 2>/dev/null'
EXPECTED_SUCCESS_LOG = 'LOG_OUT "Config File【$name】Update Successful!"'


def git_blob_sha1(raw: bytes) -> str:
    if not isinstance(raw, bytes):
        raise TypeError("upstream source must be raw bytes")
    return sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def audit_updater(raw: bytes, *, expected_blob_sha: str = KNOWN_UPSTREAM_BLOB_SHA) -> dict:
    """Safely inventory the exact known source; never rewrite or install it.

    expected_blob_sha is overridable solely for isolated fixture unit tests.
    Production caller must use the hardcoded known upstream digest and must
    STILL verify the device-installed script digest separately.
    """
    if not isinstance(raw, bytes) or len(raw) > 500_000 or len(raw) < 200:
        return {"status": "HOLD_SOURCE_INVALID", "can_instrument": False}
    if not re.fullmatch(r"[0-9a-f]{40}", expected_blob_sha):
        return {"status": "HOLD_PIN_INVALID", "can_instrument": False}
    if git_blob_sha1(raw) != expected_blob_sha:
        return {"status": "HOLD_UPSTREAM_VERSION_DRIFT", "can_instrument": False}

    # Pinning does not by itself prove this is the installed router version.
    source = raw.decode("utf-8", errors="strict")
    start = source.find("\nconfig_su_check()\n{")
    stop = source.find("\nconfig_error()\n{", start + 1)
    if start < 0 or stop <= start:
        return {"status": "HOLD_UNEXPECTED_SCRIPT_STRUCTURE", "can_instrument": False}
    scope = source[start:stop]
    if (scope.count(EXPECTED_PLAIN_MV) != 2
            or scope.count(EXPECTED_SUCCESS_LOG) != 2
            or "cmp -s \"$CONFIG_FILE\" \"$CFG_FILE\"" not in scope
            or "No Change, Do Nothing!" not in scope
            or "restart=1" not in scope
            or 'dec_job_counter_and_restart "$restart"' not in source
            or 'exit "$exit_code"' not in source):
        return {"status": "HOLD_UNEXPECTED_SCRIPT_STRUCTURE", "can_instrument": False}

    return {
        "status": "KNOWN_UPSTREAM_UNCHECKED_MOVE",
        "can_instrument": False,
        "unchecked_move_branches": 2,
        "plain_success_messages": 2,
        "version_pinned": True,
        "device_version_verified": False,
        "postcommit_hook_installed": False,
        "rollback_verified": False,
    }


def assess_postcommit_contract(
    *,
    device_updater_exactly_pinned: bool,
    protected_run_id: str | None,
    boot_id: str | None,
    download_exit_ok: bool,
    downloaded_body_validated: bool,
    transformed_yaml_validated: bool,
    commit_outcome: str,
    selected_active_source: bool,
    staged_sha256: str | None,
    committed_sha256: str | None,
    mv_exit_status: int | None,
    readback_completed: bool,
    source_config_was_changed: bool,
    marker_written_by_protected_hook: bool,
    lock_held: bool,
    rollback_backup_verified: bool,
) -> dict[str, object]:
    """Check synthetic offline postcommit event fields; ALWAYS fail closed.

    Guard against treating log success, HTTP 304, checksum comparison, or
    an mv exit code of zero as sufficient by itself. An instrumentation
    candidate still does not authenticate the caller, live core or secrets,
    nor authorize reconciliation or switching.
    """
    def result(reason: str, candidate: bool = False) -> dict[str, object]:
        return {
            "reason": reason, "postcommit_candidate": candidate,
            "trusted_installed_observer": False,
            "full_runtime_identity_proven": False,
            "allow_reconcile": False, "allow_switch": False,
            "production_writes": False,
        }

    if device_updater_exactly_pinned is not True:
        return result("HOLD_INSTALLED_UPDATER_UNVERIFIED")
    if not isinstance(protected_run_id, str) or not _RUN.fullmatch(protected_run_id):
        return result("HOLD_RUN_GENERATION_INVALID")
    if not isinstance(boot_id, str) or not _UUID.fullmatch(boot_id):
        return result("HOLD_BOOT_ID_INVALID")
    if lock_held is not True or rollback_backup_verified is not True:
        return result("HOLD_LOCK_OR_ROLLBACK_UNVERIFIED")
    if download_exit_ok is not True or downloaded_body_validated is not True:
        return result("HOLD_DOWNLOAD_NOT_VALIDATED")
    if transformed_yaml_validated is not True:
        return result("HOLD_FINAL_YAML_NOT_VALIDATED")
    if selected_active_source is not True:
        return result("HOLD_NOT_ACTIVE_SOURCE")
    if commit_outcome == "NO_CHANGE":
        # No replacement occurred. The unchanged-snapshot observer needs its
        # own validated 304/re-download path, not an invented post-move event.
        return result("HOLD_NO_NEW_COMMIT_SEPARATE_NO_CHANGE_PROOF")
    if commit_outcome != "CHANGED":
        return result("HOLD_UNSUPPORTED_COMMIT_RESULT")
    if (not isinstance(staged_sha256, str) or not _HEX256.fullmatch(staged_sha256)
            or not isinstance(committed_sha256, str) or not _HEX256.fullmatch(committed_sha256)):
        return result("HOLD_DIGEST_MISSING")
    if staged_sha256 != committed_sha256:
        return result("HOLD_POSTMOVE_BYTES_MISMATCH")
    if type(mv_exit_status) is not int or mv_exit_status != 0:
        return result("HOLD_MOVE_FAILED")
    if readback_completed is not True:
        return result("HOLD_POSTMOVE_READBACK_MISSING")
    if source_config_was_changed is not True:
        return result("HOLD_EVENT_SOURCE_INCONSISTENT")
    if marker_written_by_protected_hook is not True:
        return result("HOLD_NO_PROTECTED_COMMIT_MARKER")

    # Still only an offline contract, not a verified run of the installed updater.
    return result("POSTCOMMIT_OBSERVER_CONTRACT_CANDIDATE_ONLY", candidate=True)


if __name__ == "__main__":
    raise SystemExit("Import-only offline contract; do not run on a router.")
