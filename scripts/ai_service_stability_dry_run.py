#!/usr/bin/env python3
"""Private-input, pure offline AI service qualification and anti-flap DRY_RUN.

No IO, sockets, controller API, scheduler, filesystem writes or live switching.
The public summary deliberately contains counts and fixed status codes only.
The private target/queue MUST NOT be logged, published or sent to CI artifacts.

Only independent subscription/update/reload evidence can unlock reconciliation.
A 58/58 live NAME match (even with only one extra leaf) does not attest that
connection credentials were loaded. Homepage 200/301 is NEVER business proof.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from math import isfinite
from typing import Any

from ai_dynamic_refresh_planner import SERVICES, updated_state
from ai_refresh_transition_gate import decide_refresh
from reconcile_subscription import validate_manifest

SHARED_SERVICE = "shared_all_services"  # Existing AI parent shares a single node.
# Same-exit flags must come from the authorized browser workflow plus
# router-side connection observation, not from HTTP 200 or node naming.
# In particular, NotebookLM source import alone does not verify working
# source-grounded responses / citations.
WORKFLOW_TASKS = {
    "chatgpt": ("signed_in", "prompt_answered", "stream_completed", "route_consistent"),
    "gemini": ("signed_in", "prompt_answered", "route_consistent"),
    "notebooklm": (
        "signed_in", "workspace_opened", "source_imported",
        "question_answered", "citation_checked", "route_consistent",
    ),
}
NETWORK_TARGETS = frozenset(("dns", "tcp", "tls", "http"))
GATE_OK = frozenset(("KEEP_CURRENT_AI_CATALOG", "PLAN_INCREMENTAL_AI_ONLY"))


def moment(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            return None
        return parsed.astimezone(timezone.utc)
    except (ValueError, OverflowError):
        return None


def fresh(value: Any, now: datetime, age_seconds: int) -> bool:
    at = moment(value)
    return at is not None and timedelta(0) <= now - at <= timedelta(seconds=age_seconds)


def positive_metric(value: Any) -> bool:
    return type(value) in (float, int) and isfinite(value) and value > 0


def business_verified(proof: Any, *, service: str, fingerprint: str, now: datetime) -> bool:
    """Requires an independent, unexpired real-user workflow attestation.

    This is a validator of externally produced evidence, NOT a detector and
    NOT a substitute for real account login/generation/upload observations.
    """
    if not isinstance(proof, dict):
        return False
    expiry = moment(proof.get("expires_at"))
    checks = proof.get("checks")
    return (
        proof.get("status") == "BUSINESS_VERIFIED"
        and proof.get("fingerprint") == fingerprint
        and proof.get("method") == "user_interactive_workflow"
        and fresh(proof.get("observed_at"), now, 24 * 3600)
        and expiry is not None and now < expiry <= now + timedelta(days=7)
        and isinstance(checks, dict)
        and all(checks.get(task) is True for task in WORKFLOW_TASKS[service])
    )


def qualified_pool(
    manifest: dict, state: dict, observations: dict, live_names: set[str],
    *, service: str, region: str, now: datetime
) -> list[dict]:
    """PRIVATE qualified sorted node rows. Caller never prints them."""
    wanted = manifest["node_fingerprints"]
    candidates = []
    for name, fingerprint in wanted.items():
        if name not in live_names:
            continue
        entry = state.get(name)
        obs = observations.get(name)
        if not isinstance(entry, dict) or not isinstance(obs, dict):
            continue
        if entry.get("fingerprint") != fingerprint or obs.get("fingerprint") != fingerprint:
            continue
        service_proofs = entry.get("services")
        if not isinstance(service_proofs, dict):
            continue
        required = SERVICES if service == SHARED_SERVICE else (service,)
        if not all(business_verified(service_proofs.get(svc), service=svc,
                                     fingerprint=fingerprint, now=now)
                   for svc in required):
            continue
        geo = obs.get("egress")
        if not isinstance(geo, dict) or geo.get("fingerprint") != fingerprint or geo.get("verified") is not True:
            continue
        cc = geo.get("country")
        if not isinstance(cc, str) or len(cc) != 2 or not cc.isascii() or not cc.isupper():
            continue
        if region != "GLOBAL" and cc != region:
            continue
        if not fresh(geo.get("observed_at"), now, 24 * 3600):
            continue
        if type(geo.get("independent_sources")) is not int or geo["independent_sources"] < 2:
            continue
        health = obs.get("health")
        if not isinstance(health, dict) or health.get("fingerprint") != fingerprint:
            continue
        if not fresh(health.get("observed_at"), now, 20 * 60):
            continue
        if type(health.get("samples")) is not int or health["samples"] < 5:
            continue
        rate = health.get("success_rate")
        p95 = health.get("rtt_p95_ms")
        if type(rate) not in (float, int) or not isfinite(rate) or not 0.95 <= rate <= 1:
            continue
        if not positive_metric(p95):
            continue
        speed = health.get("throughput_mbps", 0)
        if type(speed) not in (float, int) or not isfinite(speed) or speed < 0:
            speed = 0
        multiplier = obs.get("cost_multiplier", 1)
        if not positive_metric(multiplier):
            multiplier = 1
        candidates.append({
            "name": name, "fingerprint": fingerprint, "country": cc,
            "rank": (-rate, p95, -speed, multiplier, name),
        })
    return sorted(candidates, key=lambda row: row["rank"])


def failure_evidence(events: Any, *, node: str, fingerprint: str, now: datetime) -> tuple[int, int]:
    """Independent, recent node-network failures on multiple target classes."""
    if not isinstance(events, list):
        return 0, 0
    unique = set()
    for entry in events:
        if not isinstance(entry, dict):
            continue
        if entry.get("node") != node or entry.get("fingerprint") != fingerprint:
            continue
        if entry.get("kind") != "node_network" or entry.get("target") not in NETWORK_TARGETS:
            continue
        if not fresh(entry.get("observed_at"), now, 120):
            continue
        unique.add((entry["observed_at"], entry["target"]))
    return len(unique), len({t for _, t in unique})


def plan_dry_run(
    *,
    previous_manifest: dict | None,
    current_manifest: dict,
    previous_state: dict,
    observations: dict,
    live_names: set[str],
    refresh_signals: dict,
    coverage_verified: bool,
    service: str,
    region: str,
    current: str,
    mode: str,
    ai_parent_selected_stable: bool,
    state_history_ready: bool,
    current_healthy: bool,
    global_incident: bool,
    selected_since: str | None,
    cooldown_until: str | None,
    failure_events: list[dict],
    now: datetime,
) -> dict:
    """Return {public: anonymous summary, private_target, private_probe_queue}.

    Always DRY_RUN. A proposed private target is not a license to PUT.
    All input dictionaries with IDs/credentials must remain private.
    """
    if now.tzinfo is None:
        raise ValueError("aware UTC time required")
    now = now.astimezone(timezone.utc)
    if service not in (*SERVICES, SHARED_SERVICE) or not isinstance(region, str) or (
        region != "GLOBAL" and
        (len(region) != 2 or not region.isascii() or not region.isupper())):
        raise ValueError("invalid service or region")
    for key, value in {"ai_parent_selected_stable": ai_parent_selected_stable,
                       "state_history_ready": state_history_ready,
                       "current_healthy": current_healthy,
                       "global_incident": global_incident}.items():
        if type(value) is not bool:
            raise ValueError(f"invalid fail-closed signal: {key}")
    validate_manifest(current_manifest)
    if previous_manifest is not None:
        validate_manifest(previous_manifest)
    if type(coverage_verified) is not bool:
        raise ValueError("coverage gate must be boolean")
    if not isinstance(live_names, set) or not all(isinstance(x, str) for x in live_names):
        raise ValueError("invalid private live-name set")

    expected = set(current_manifest["node_fingerprints"])
    extra = len(live_names - expected)
    public = {"decision": "HOLD_UNVERIFIED", "gate": "UNVERIFIED",
              "expected_names": len(expected), "present_names": len(expected & live_names),
              "extra_untrusted": extra, "qualified_candidates": 0,
              "live_writes": False, "ai_switch": False}
    def result(reason: str, *, gate: str | None = None,
               private_target: str | None = None,
               queue: list[str] | None = None) -> dict:
        public["decision"] = reason
        if gate is not None:
            public["gate"] = gate
        return {"public": dict(public), "private_target": private_target,
                "private_probe_queue": list(queue or [])}

    # First gates are not derived from live names; extras are always excluded.
    if coverage_verified is not True:
        return result("HOLD_SOURCE_COVERAGE")
    if not isinstance(refresh_signals, dict):
        return result("HOLD_UPDATE_EVIDENCE")
    gate = decide_refresh(**refresh_signals)
    if gate["decision"] not in GATE_OK:
        return result("HOLD_UPDATE_EVIDENCE", gate=gate["decision"])
    if expected - live_names:
        return result("HOLD_MISSING_LIVE_NAMES", gate=gate["decision"])
    if previous_manifest is not None:
        changed_identities = (previous_manifest["node_fingerprints"] !=
                              current_manifest["node_fingerprints"])
        if changed_identities and (
            refresh_signals.get("update_event") != "UPDATED" or
            refresh_signals.get("source_changed") is not True
        ):
            return result("HOLD_MANIFEST_EVENT_INCONSISTENT", gate=gate["decision"])

    # Reuse existing fingerprint-based state carry-forward. Never call this
    # with guessed success/reload flags, regardless of matching node names.
    state, _, queue = updated_state(
        previous_manifest, current_manifest, previous_state,
        update_succeeded=True, runtime_loaded=True, now=now,
    )
    if not isinstance(observations, dict):
        return result("HOLD_INVALID_OBSERVATIONS", gate=gate["decision"])
    pool = qualified_pool(current_manifest, state, observations, live_names,
                          service=service, region=region, now=now)
    public["qualified_candidates"] = len(pool)
    private_queue = queue

    if mode != "AUTO" or ai_parent_selected_stable is not True:
        return result("HOLD_MANUAL", gate=gate["decision"], queue=private_queue)
    if state_history_ready is not True:
        return result("HOLD_UNINITIALIZED_HISTORY", gate=gate["decision"], queue=private_queue)
    if current not in expected:
        return result("HOLD_CURRENT_NOT_IN_TRUSTED_MANIFEST", gate=gate["decision"], queue=private_queue)
    if current_healthy is True:
        return result("HOLD_HEALTHY_STICKY", gate=gate["decision"], queue=private_queue)
    if global_incident is not False:
        return result("HOLD_SHARED_OR_UNKNOWN_OUTAGE", gate=gate["decision"], queue=private_queue)

    count, distinct_targets = failure_evidence(
        failure_events, node=current, fingerprint=current_manifest["node_fingerprints"][current], now=now
    )
    if count < 3 or distinct_targets < 2:
        return result("HOLD_INSUFFICIENT_NODE_EVIDENCE", gate=gate["decision"], queue=private_queue)
    if selected_since is None or moment(selected_since) is None:
        return result("HOLD_DWELL_UNVERIFIED", gate=gate["decision"], queue=private_queue)
    selected = moment(selected_since)
    if selected > now or now - selected < timedelta(minutes=30):
        return result("HOLD_MINIMUM_DWELL", gate=gate["decision"], queue=private_queue)
    if cooldown_until is not None:
        cooldown = moment(cooldown_until)
        if cooldown is None:
            return result("HOLD_INVALID_COOLDOWN", gate=gate["decision"], queue=private_queue)
        if now < cooldown:
            return result("HOLD_COOLDOWN", gate=gate["decision"], queue=private_queue)
    # In country-locked mode, an unqualified current node still must actually
    # be in that region before any same-country failover is planned.
    if region != "GLOBAL":
        current_obs = observations.get(current)
        geo = current_obs.get("egress") if isinstance(current_obs, dict) else None
        if not isinstance(geo, dict) or geo.get("country") != region or geo.get("verified") is not True or \
           geo.get("fingerprint") != current_manifest["node_fingerprints"][current] or \
           not fresh(geo.get("observed_at"), now, 24 * 3600) or \
           type(geo.get("independent_sources")) is not int or geo["independent_sources"] < 2:
            return result("HOLD_CURRENT_REGION_UNVERIFIED", gate=gate["decision"], queue=private_queue)
    backup = next((n["name"] for n in pool if n["name"] != current), None)
    if backup is None:
        return result("NO_BUSINESS_VERIFIED_BACKUP", gate=gate["decision"], queue=private_queue)
    return result("DRY_RUN_SWITCH_CANDIDATE", gate=gate["decision"],
                  private_target=backup, queue=private_queue)


if __name__ == "__main__":
    raise SystemExit("Pure offline test library only; never a live router or scheduling command.")
