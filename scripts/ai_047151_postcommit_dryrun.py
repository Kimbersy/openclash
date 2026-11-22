#!/usr/bin/env python3
"""0.47.151 post-commit observation: strictly OFFLINE transaction rehearsal.

This code is NOT a hook, downloader, installer, or a router command. All
inputs are synthetic event records. This verifies when a future *protected*
observer should classify the local file commit as a candidate, including
failure/crash/no-change/rollback. It does not authenticate event provenance or
authorize runtime reconciliation / live switching. Keep private IDs and hashes
out of result text.
"""
from __future__ import annotations

from typing import Any
from ai_openclash_updater_contract import (
    KNOWN_DEVICE_UPDATER_BLOB_SHA, assess_postcommit_contract
)

STEPS = ("download", "yaml_validated", "move", "readback")
REQUIRE = frozenset(STEPS)


def assess_transaction(trace: Any) -> dict[str, object]:
    def hold(reason: str, *, candidate: bool = False) -> dict[str, object]:
        return {
            "stage": reason,
            "local_commit_candidate": candidate,
            "runtime_identity_proven": False,
            "allow_reconcile": False, "allow_switch": False,
            "production_writes": False,
        }

    if not isinstance(trace, dict):
        return hold("HOLD_NO_TRANSACTION")
    if trace.get("installed_updater_blob") != KNOWN_DEVICE_UPDATER_BLOB_SHA:
        return hold("HOLD_VERSION_DRIFT")
    if trace.get("locked") is not True or trace.get("rollback_backup") is not True:
        return hold("HOLD_LOCK_OR_BACKUP")
    if trace.get("interrupted") is True or trace.get("rebooted") is True:
        return hold("HOLD_INTERRUPTED")
    if trace.get("rollback_started") is True:
        return hold("HOLD_ROLLBACK")
    if trace.get("overlapping_run") is True:
        return hold("HOLD_CONCURRENT")
    outcome = trace.get("outcome")
    if outcome == "NO_CHANGE":
        # No mv occurred; not a new post-commit event.
        return hold("UNCHANGED_NO_NEW_COMMIT")
    if outcome != "CHANGED":
        return hold("HOLD_UPDATE_FAILED_OR_UNKNOWN")
    events = trace.get("events")
    if (not isinstance(events, list)
            or len(events) != len(STEPS)
            or any(not isinstance(row, dict) for row in events)):
        return hold("HOLD_MISSING_STAGES")
    seen = [row.get("stage") for row in events]
    if tuple(seen) != STEPS or len(set(seen)) != len(STEPS):
        return hold("HOLD_STAGE_ORDER")
    run_id, boot_id = trace.get("run_id"), trace.get("boot_id")
    if any(row.get("run_id") != run_id or row.get("boot_id") != boot_id
           for row in events):
        return hold("HOLD_RUN_GENERATION_MISMATCH")
    ticks = [row.get("tick") for row in events]
    if any(type(tick) is not int or tick < 0 for tick in ticks):
        return hold("HOLD_CLOCK_UNVERIFIED")
    if ticks != sorted(ticks) or len(set(ticks)) != len(ticks):
        return hold("HOLD_STAGE_ORDER")
    verdict = assess_postcommit_contract(
        device_updater_exactly_pinned=True,
        protected_run_id=run_id,
        boot_id=boot_id,
        download_exit_ok=events[0].get("ok"),
        downloaded_body_validated=events[0].get("body_valid"),
        transformed_yaml_validated=events[1].get("ok"),
        commit_outcome=outcome,
        selected_active_source=trace.get("selected_active_source"),
        staged_sha256=events[2].get("staged_sha256"),
        committed_sha256=events[3].get("committed_sha256"),
        mv_exit_status=events[2].get("exit_code"),
        readback_completed=events[3].get("ok"),
        source_config_was_changed=trace.get("source_changed"),
        marker_written_by_protected_hook=trace.get("protected_hook"),
        lock_held=trace.get("locked"),
        rollback_backup_verified=trace.get("rollback_backup"),
    )
    if verdict["postcommit_candidate"]:
        return hold("LOCAL_POSTCOMMIT_CONTRACT_CANDIDATE_ONLY", candidate=True)
    return hold("HOLD_POSTCOMMIT_EVIDENCE")


if __name__ == "__main__":
    raise SystemExit("Offline-only rehearsal library; no router activity.")
