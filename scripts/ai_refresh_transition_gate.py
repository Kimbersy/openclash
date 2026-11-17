#!/usr/bin/env python3
"""Fail-closed decisions for post-subscription AI-only incremental refresh.

No network, files, config writes or router controller calls.
The caller supplies independently observed signals. This is *not* an
automatic event collector or evidence of router deployment.
"""
from __future__ import annotations
from typing import Any

EVENTS = frozenset(("UPDATED", "NO_CHANGE", "ERROR", "UNKNOWN"))
DECISIONS = frozenset((
    "HOLD_UPDATE_UNCONFIRMED", "HOLD_REMOTE_ERROR", "HOLD_DISK_MISMATCH",
    "HOLD_RUNTIME_UNVERIFIED", "HOLD_UNSTABLE_SNAPSHOT",
    "HOLD_EVENT_SOURCE_INCONSISTENT", "HOLD_NON_AI_INVARIANT_BREACH", "PLAN_INCREMENTAL_AI_ONLY",
    "KEEP_CURRENT_AI_CATALOG",
))


def decide_refresh(
    *,
    update_event: str,
    source_changed: bool,
    source_runtime_disk_equal: bool,
    live_api_reachable: bool,
    live_membership_matches: bool,
    full_runtime_reload_confirmed: bool,
    stable_snapshot_samples: int,
    non_ai_changes: int = 0,
) -> dict[str, Any]:
    """Evaluate a verified-source transition without performing one.

    All event flags are trusted external evidence, *not* gathered here.
    OpenClash log message 'Update Successful' only attests a code path that
    attempts to write a file; it DOES NOT prove remote update success on its
    own, nor that Mihomo loaded changed proxy credentials.

    Full runtime reload confirmation requires an independent real-runtime
    signal tied to the same source fingerprint, never just a node-count match.
    """
    if update_event not in EVENTS:
        raise ValueError("invalid remote update event classification")
    for label, flag in {
        "source_changed": source_changed,
        "source_runtime_disk_equal": source_runtime_disk_equal,
        "live_api_reachable": live_api_reachable,
        "live_membership_matches": live_membership_matches,
        "full_runtime_reload_confirmed": full_runtime_reload_confirmed,
    }.items():
        if type(flag) is not bool:
            raise ValueError(f"invalid boolean signal: {label}")
    if type(stable_snapshot_samples) is not int or stable_snapshot_samples < 0:
        raise ValueError("invalid stable snapshot evidence")
    if type(non_ai_changes) is not int or non_ai_changes < 0:
        raise ValueError("invalid non-AI diff count")
    if non_ai_changes != 0:
        return {
            "decision": "HOLD_NON_AI_INVARIANT_BREACH",
            "ai_catalog_apply": False,
            "plan_reconciliation": False,
            "preserve_non_ai": True,
        }
    if update_event == "ERROR":
        decision = "HOLD_REMOTE_ERROR"
    elif update_event == "UNKNOWN":
        decision = "HOLD_UPDATE_UNCONFIRMED"
    elif not source_runtime_disk_equal:
        decision = "HOLD_DISK_MISMATCH"
    elif not (live_api_reachable and live_membership_matches and full_runtime_reload_confirmed):
        decision = "HOLD_RUNTIME_UNVERIFIED"
    elif stable_snapshot_samples < 2:
        decision = "HOLD_UNSTABLE_SNAPSHOT"
    elif update_event == "NO_CHANGE" and not source_changed:
        decision = "KEEP_CURRENT_AI_CATALOG"
    elif update_event == "UPDATED" and source_changed:
        decision = "PLAN_INCREMENTAL_AI_ONLY"
    else:
        decision = "HOLD_EVENT_SOURCE_INCONSISTENT"

    return {
        "decision": decision,
        # Even a plan is never permission for live route switching. The only
        # effects authorized by this module are offline reconciliation plans.
        "ai_catalog_apply": False,
        "plan_reconciliation": decision == "PLAN_INCREMENTAL_AI_ONLY",
        "preserve_non_ai": True,
    }


if __name__ == "__main__":
    raise SystemExit("Offline library only; no OpenClash or client action.")
