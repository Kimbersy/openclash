#!/usr/bin/env python3
"""AI-only refresh safety gate. Offline, NO I/O, NO network, NO routing changes.

Events must be produced by separately VERIFIED, authenticated local sources:
- a successful OpenClash subscription download/validation/commit observer
- an independent currently running Mihomo controller/provider snapshot observer
A UI 'update started', a log substring, disk mtime, PID or YAML equality cannot
substitute for either observer. This gate never confers AI business qualification.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import re

from reconcile_subscription import validate_manifest

_HEX = re.compile(r"[0-9a-f]{64}\Z")
_EVENT = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{3,127}\Z")
_UPDATE_SOURCE = "verified_openclash_commit_observer"
_RUNTIME_SOURCE = "authenticated_live_mihomo_snapshot"
_VALID_UPDATES = frozenset(("VALIDATED_CHANGED", "VALIDATED_NO_CHANGE"))


def _stamp(value):
    if not isinstance(value, str):
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt.astimezone(timezone.utc) if dt.tzinfo is not None else None


def _fingerprint(value):
    return isinstance(value, str) and _HEX.fullmatch(value) is not None


def _id(value):
    return isinstance(value, str) and _EVENT.fullmatch(value) is not None


def catalog_digest(manifest: dict) -> str:
    """Hash canonical name->FULL connection fingerprints, never raw YAML bytes.

    OpenClash may rewrite DNS/groups/metadata between subscribed and running
    YAML. The adapter must separately read LIVE Mihomo nodes and calculate the
    same canonical map digest; a copy of the disk file is not runtime proof.
    """
    validate_manifest(manifest)
    payload = json.dumps(
        manifest["node_fingerprints"], sort_keys=True, ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def assess(
    manifest: dict,
    update_event: dict | None,
    runtime_event: dict | None,
    *,
    source_coverage_verified: bool,
    now: datetime | None = None,
    max_age_seconds: int = 24 * 3600,
) -> dict:
    """Return only anonymous status/reasons; never echo tokens/node data.

    An accepted result only permits reconciliation of a *private* snapshot;
    it is NOT permission to publish configs, select a proxy, or mark AI usable.
    """
    now = now if now is not None else datetime.now(timezone.utc)
    if now.tzinfo is None or not 60 <= max_age_seconds <= 86_400:
        raise ValueError("invalid time gate parameters")

    def stop(reason):
        return {"status": "HOLD_NO_REFRESH_PROOF", "reason": reason,
                "allow_reconcile": False, "allow_switch": False}

    try:
        validate_manifest(manifest)
    except (TypeError, ValueError, KeyError):
        return stop("BAD_MANIFEST")

    if source_coverage_verified is not True:
        return stop("INCOMPLETE_SOURCE_COVERAGE")
    if not isinstance(update_event, dict):
        return stop("MISSING_UPDATE_EVENT")
    if (update_event.get("source") != _UPDATE_SOURCE
            or update_event.get("result") not in _VALID_UPDATES
            or update_event.get("validated_download") is not True
            or update_event.get("committed") is not True
            or not _id(update_event.get("run_id"))):
        return stop("UPDATE_NOT_PROVEN")

    observed = _stamp(update_event.get("finished_at"))
    if observed is None or not 0 <= (now - observed).total_seconds() <= max_age_seconds:
        return stop("STALE_UPDATE_EVENT")
    snapshot = manifest.get("subscription_snapshot", {})
    manifest_hash = snapshot.get("sha256") if isinstance(snapshot, dict) else None
    if not _fingerprint(manifest_hash) or update_event.get("snapshot_sha256") != manifest_hash:
        return stop("UPDATE_SNAPSHOT_MISMATCH")

    if not isinstance(runtime_event, dict):
        return stop("MISSING_RUNTIME_EVIDENCE")
    if (runtime_event.get("source") != _RUNTIME_SOURCE
            or runtime_event.get("core_running") is not True
            or runtime_event.get("authenticated") is not True
            or runtime_event.get("all_providers_loaded") is not True
            or runtime_event.get("run_id") != update_event["run_id"]):
        return stop("RUNTIME_NOT_PROVEN")

    loaded_at = _stamp(runtime_event.get("observed_at"))
    if (loaded_at is None or loaded_at < observed
            or not 0 <= (now - loaded_at).total_seconds() <= max_age_seconds):
        return stop("RUNTIME_EVIDENCE_STALE_OR_PREUPDATE")
    if runtime_event.get("live_node_identity_digest") != catalog_digest(manifest):
        return stop("LIVE_NODE_IDENTITY_MISMATCH")

    return {"status": "VERIFIED_SNAPSHOT_READY", "reason": "PROOF_GATES_PASSED",
            "allow_reconcile": True, "allow_switch": False}


if __name__ == "__main__":
    raise SystemExit("Import-only safety gate; no OpenClash or Mihomo interaction.")
