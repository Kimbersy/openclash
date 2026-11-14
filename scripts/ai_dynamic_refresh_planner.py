#!/usr/bin/env python3
"""Offline AI candidate-state reconciliation after a *verified live* subscription reload.

This module performs NO networking, writes, API calls or production switching.
Private node identities and service records must never be published or logged.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from reconcile_subscription import compare_manifests, validate_manifest

SERVICES = ("chatgpt", "gemini", "notebooklm")
VALID_STATUSES = frozenset(("UNKNOWN", "NETWORK_CANDIDATE", "BUSINESS_VERIFIED", "DEGRADED", "BLOCKED"))


def active_timestamp(value: Any, now: datetime) -> bool:
    """Require an explicit future expiry for all inherited evidence."""
    if not isinstance(value, str):
        return False
    try:
        expiry = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return False
    return expiry.tzinfo is not None and expiry > now


def updated_state(
    previous_manifest: dict | None,
    current_manifest: dict,
    previous_state: dict[str, dict],
    *,
    update_succeeded: bool,
    runtime_loaded: bool,
    now: datetime | None = None,
) -> tuple[dict[str, dict], dict[str, int | bool], list[str]]:
    """Return a PRIVATE state, anonymous metrics and a PRIVATE probe queue.

    Source update success and exact active-core equivalence are external evidence
    gates. A mere file mtime, 58-node count or downloaded YAML is not enough.
    Matching full connection fingerprints may carry *unexpired* observations,
    even when the raw subscription snapshot/order/comments changed.
    """
    if update_succeeded is not True or runtime_loaded is not True:
        raise ValueError("subscription not confirmed loaded into the running core")
    validate_manifest(current_manifest)
    if previous_manifest is not None:
        validate_manifest(previous_manifest)
    if not isinstance(previous_state, dict):
        raise ValueError("private state must be a mapping")
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is None:
        raise ValueError("now must be timezone aware")

    stats = compare_manifests(previous_manifest, current_manifest)
    after = current_manifest["node_fingerprints"]
    before = previous_manifest["node_fingerprints"] if previous_manifest is not None else {}

    state: dict[str, dict] = {}
    probe_queue = []
    retained_services = expired_services = reset_services = 0
    changed_identical_name = 0

    for name, fingerprint in after.items():
        old = previous_state.get(name)
        identity_kept = before.get(name) == fingerprint
        if name in before and not identity_kept:
            changed_identical_name += 1
        carry = old if isinstance(old, dict) and identity_kept and old.get("fingerprint") == fingerprint else None
        services = {}
        for svc in SERVICES:
            evidence = carry.get("services", {}).get(svc) if isinstance(carry, dict) and isinstance(carry.get("services"), dict) else None
            if (isinstance(evidence, dict)
                    and evidence.get("status") in VALID_STATUSES - {"UNKNOWN"}
                    and active_timestamp(evidence.get("expires_at"), now)
                    and evidence.get("fingerprint") == fingerprint):
                services[svc] = dict(evidence)
                retained_services += 1
            else:
                services[svc] = {"status": "UNKNOWN", "fingerprint": fingerprint}
                if carry and isinstance(evidence, dict):
                    expired_services += 1
                else:
                    reset_services += 1
        state[name] = {"fingerprint": fingerprint, "services": services}
        if not identity_kept or any(x["status"] == "UNKNOWN" for x in services.values()):
            probe_queue.append(name)

    # No implicit selection mutation: a missing selected node is a caller-side
    # MANUAL_BLOCKED / NO_VERIFIED_BACKUP decision, not a reason to hop regions.
    metrics = {
        "current": len(after),
        "added": stats["added"],
        "removed": stats["removed"],
        "replaced_same_name": changed_identical_name,
        "unchanged": stats["unchanged"],
        "raw_snapshot_changed": stats["source_changed"],
        "service_evidence_retained": retained_services,
        "service_evidence_expired": expired_services,
        "service_evidence_reset": reset_services,
        "nodes_queued_for_recheck": len(probe_queue),
    }
    return state, metrics, probe_queue


if __name__ == "__main__":
    raise SystemExit("Pure offline library only; no scheduler installed or router action executed.")
