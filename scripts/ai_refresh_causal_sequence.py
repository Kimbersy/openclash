#!/usr/bin/env python3
"""Pure, conservative natural-refresh -> process cold-start causal chain.

Never contacts OpenClash/Mihomo, writes routes or asserts live credentials.
A log line, mtime, 58/58 names or a successful API GET cannot authenticate
a download/commit. Future trusted local observers are NOT installed yet.
Even a perfect cold-start chronology is only a CANDIDATE, not permission
for private reconciliation or any runtime node switching.
"""
from __future__ import annotations

import re
from typing import Any

_HEX64 = re.compile(r"[a-f0-9]{64}\Z")
_RUN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{3,127}\Z")
_BOOT = re.compile(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\Z")


def _valid(value: Any, pattern: re.Pattern) -> bool:
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def _tick(value: Any) -> bool:
    return type(value) is int and value >= 0


def assess_natural_refresh(
    *, update: dict | None, core: dict | None, api: dict | None,
    current_boot_id: str | None, hz_from_kernel_auxv: int | None,
    sample_now_ticks: int | None, source_snapshot_sha256: str | None,
    runtime_render_sha256: str | None, source_coverage_verified: bool,
    non_ai_changes: int | None,
) -> dict[str, object]:
    """Correlate independently collected PRIVATE events without claiming reload.

    Trusted post-commit observer and process/credential attestor do not exist
    on the router. Text 'source' tags/booleans supplied by a caller are only a
    simulated CONTRACT, not authenticity, until the provenance is verified.
    This code will NEVER authorize reconciliation or switching.
    """
    def hold(reason: str) -> dict[str, object]:
        return {"stage": reason, "cold_start_candidate": False,
                "runtime_identity_proven": False, "allow_reconcile": False,
                "allow_switch": False, "writes": False}

    if source_coverage_verified is not True:
        return hold("HOLD_SOURCE_COVERAGE")
    if type(non_ai_changes) is not int or non_ai_changes != 0:
        return hold("HOLD_NON_AI_INVARIANT")
    if not isinstance(update, dict):
        return hold("HOLD_NO_POSTCOMMIT_OBSERVER")
    if (update.get("source") != "instrumented_openclash_postcommit"
            or update.get("verified_download") is not True
            or update.get("validated_write") is not True
            or update.get("atomic_commit_verified") is not True
            or update.get("latest_event") != "VALIDATED_CHANGED"
            or not _valid(update.get("run_id"), _RUN)):
        return hold("HOLD_UPDATE_COMMIT_UNVERIFIED")
    if not _valid(source_snapshot_sha256, _HEX64):
        return hold("HOLD_SOURCE_HASH_UNVERIFIED")
    if update.get("source_sha256") != source_snapshot_sha256:
        return hold("HOLD_SOURCE_HASH_MISMATCH")
    if not _valid(current_boot_id, _BOOT):
        return hold("HOLD_BOOT_UNVERIFIED")
    if update.get("boot_id") != current_boot_id:
        return hold("HOLD_BOOT_CHANGED")
    if (type(hz_from_kernel_auxv) is not int
            or not 10 <= hz_from_kernel_auxv <= 10_000
            or not _tick(sample_now_ticks)):
        return hold("HOLD_KERNEL_CLOCK_UNVERIFIED")
    commit = update.get("commit_ticks")
    if not _tick(commit) or commit >= sample_now_ticks:
        return hold("HOLD_COMMIT_CLOCK_INVALID")
    if sample_now_ticks - commit > hz_from_kernel_auxv * 3600:
        return hold("HOLD_COMMIT_TOO_OLD")
    if not isinstance(core, dict) or core.get("boot_id") != current_boot_id:
        return hold("HOLD_CORE_BOOT_OR_RECORD")
    if (core.get("only_production_core") is not True
            or core.get("executable_verified") is not True
            or core.get("source_run_id") != update["run_id"]):
        return hold("HOLD_CORE_PROVENANCE")
    started = core.get("start_ticks")
    checked = core.get("checked_ticks")
    if not _tick(started) or not _tick(checked):
        return hold("HOLD_CORE_CLOCK_UNVERIFIED")
    if not (commit < started <= checked <= sample_now_ticks):
        return hold("HOLD_CORE_NOT_STARTED_AFTER_COMMIT")
    if core.get("config_unchanged_during_start") is not True:
        return hold("HOLD_RUNTIME_FILE_CONCURRENT_CHANGE")
    if not _valid(runtime_render_sha256, _HEX64):
        return hold("HOLD_RUNTIME_DISK_UNVERIFIED")
    if core.get("runtime_file_sha256") != runtime_render_sha256:
        return hold("HOLD_RUNTIME_FILE_MISMATCH")
    if not isinstance(api, dict) or api.get("boot_id") != current_boot_id:
        return hold("HOLD_RUNTIME_API_UNVERIFIED")
    if (api.get("core_identity_matches") is not True
            or api.get("socket_owned_by_production_pid") is not True
            or api.get("authenticated_get") is not True
            or api.get("expected_disk_names_present") is not True
            or api.get("two_stable_reads") is not True):
        return hold("HOLD_RUNTIME_API_UNVERIFIED")
    if api.get("core_run_id") != update["run_id"]:
        return hold("HOLD_RUNTIME_GENERATION_MISMATCH")
    if not _tick(api.get("read_ticks")) or not (checked <= api["read_ticks"] <= sample_now_ticks):
        return hold("HOLD_RUNTIME_API_CLOCK_INVALID")
    # GET /proxies does not expose full passwords/TLS/transport definitions.
    # Native kernel timing and source/runtime DISK hashes cannot fill that gap.
    return {"stage": "COLD_START_CHRONOLOGY_CANDIDATE_ONLY",
            "cold_start_candidate": True, "runtime_identity_proven": False,
            "allow_reconcile": False, "allow_switch": False, "writes": False}


if __name__ == "__main__":
    raise SystemExit("Pure offline library only; never a router command.")
