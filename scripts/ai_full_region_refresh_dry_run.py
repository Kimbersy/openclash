#!/usr/bin/env python3
"""Router P0: OFFLINE full qualified AI catalog -> dynamic country groups after verified refresh.

All inputs are PRIVATE. No filesystem IO, subscriptions, controller calls, downloads,
router writes or automatic selection. Caller-supplied readiness flags and refresh
events do NOT constitute evidence or authorize deployment. Current iStoreOS still
has no attested full credential reload/update postcommit event.

Existing shared AI select is preserved, with ONLY the new common three-service
groups appended as opt-in choices. Service-specific groups are materialized but
not wired into shared AI rules: Google cross-domain sessions can require one exit.
Real-country verification and actual user-workflow business evidence come from
the existing qualified_pool validator, not node labels or HTTP 204.
"""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
from typing import Any

from ai_dynamic_refresh_planner import SERVICES, updated_state
from ai_refresh_transition_gate import decide_refresh
from ai_service_stability_dry_run import SHARED_SERVICE, qualified_pool
from build_router_ai_p0_candidate import PARENT, HEALTH_URL, fingerprint
from reconcile_subscription import validate_manifest

SERVICE_GROUP_LABEL = {
    "chatgpt": "ChatGPT",
    "gemini": "Gemini",
    "notebooklm": "NotebookLM",
}
VALID_EVENT_DECISIONS = frozenset(("KEEP_CURRENT_AI_CATALOG", "PLAN_INCREMENTAL_AI_ONLY"))
PFX = "🛡️AI·"
HOLD_NAME_CONFLICT = "HOLD_AI_NAME_COLLISION"


def group_name(service: str, country: str) -> str:
    if service not in (*SERVICES, SHARED_SERVICE):
        raise ValueError("unrecognized service")
    if country != "GLOBAL" and (
        not isinstance(country, str) or len(country) != 2
        or not country.isascii() or not country.isupper()
    ):
        raise ValueError("untrusted country")
    region = "全局" if country == "GLOBAL" else country
    if service == SHARED_SERVICE:
        return f"{PFX}{region}稳态"
    return f"{PFX}{SERVICE_GROUP_LABEL[service]}·{region}"


def plan_full_ai_region_refresh(
    *,
    config: dict,
    previous_manifest: dict | None,
    current_manifest: dict,
    previous_state: dict,
    observations: dict,
    live_names: set[str],
    refresh_signals: dict,
    coverage_verified: bool,
    now: datetime,
) -> dict[str, object]:
    """Anonymous dry-run summary + detached private candidate and incremental queue.

    NO caller may interpret 'OFFLINE_CANDIDATE_ONLY' as approval to install,
    reload the device, perform a PUT, activate a group, or update credentials.
    """
    if not isinstance(config, dict) or not isinstance(now, datetime) or now.tzinfo is None:
        raise ValueError("invalid private inputs")
    if type(coverage_verified) is not bool:
        raise ValueError("invalid coverage flag")
    validate_manifest(current_manifest)
    if previous_manifest is not None:
        validate_manifest(previous_manifest)
    if not isinstance(previous_state, dict) or not isinstance(observations, dict):
        raise ValueError("invalid private state")
    if not isinstance(live_names, set) or not all(isinstance(x, str) for x in live_names):
        raise ValueError("invalid runtime catalog")
    now = now.astimezone(timezone.utc)
    initial = deepcopy(config)

    def hold(reason: str) -> dict[str, object]:
        return {
            "public": {
                "decision": reason, "all_sources_covered": False,
                "qualified_group_count": 0, "qualified_leaf_count": 0,
                "live_apply": False, "switch": False, "non_ai_mutation": False,
            },
            "private_candidate": initial,
            "private_state": None,
            "private_probe_queue": [],
        }

    if not coverage_verified:
        return hold("HOLD_SOURCE_COVERAGE")
    if not isinstance(refresh_signals, dict):
        return hold("HOLD_REFRESH_EVIDENCE")
    try:
        gate = decide_refresh(**refresh_signals)
    except (TypeError, ValueError):
        return hold("HOLD_REFRESH_EVIDENCE")
    if gate["decision"] not in VALID_EVENT_DECISIONS:
        return hold("HOLD_REFRESH_EVIDENCE")

    wanted = current_manifest["node_fingerprints"]
    prior_snapshot = (previous_manifest["subscription_snapshot"]
                      if previous_manifest is not None else None)
    current_snapshot = current_manifest["subscription_snapshot"]
    if previous_manifest is not None:
        if refresh_signals["source_changed"] != (prior_snapshot != current_snapshot):
            return hold("HOLD_EVENT_SNAPSHOT_MISMATCH")
        changed_ids = (previous_manifest["node_fingerprints"] != wanted)
        if changed_ids and refresh_signals["update_event"] != "UPDATED":
            return hold("HOLD_MANIFEST_UPDATE_EVENT_MISMATCH")
    if not isinstance(config.get("proxies"), list) or not isinstance(config.get("proxy-groups"), list):
        return hold("HOLD_SOURCE_LAYOUT")
    # Providers require separate loaded-provider attestation and full source
    # reconciliation. Never silently drop them while claiming FULL coverage.
    if config.get("proxy-providers") not in (None, {}):
        return hold("HOLD_PROVIDER_SUPPORT_NOT_ATTESTED")

    actual = {}
    for node in config["proxies"]:
        if not isinstance(node, dict) or not isinstance(node.get("name"), str) or not node["name"] or node["name"] in actual:
            return hold("HOLD_AMBIGUOUS_PROXY")
        actual[node["name"]] = node
    if set(actual) != set(wanted):
        return hold("HOLD_SOURCE_IDENTITY_MISMATCH")
    if any(fingerprint(actual[n]) != fp for n, fp in wanted.items()):
        return hold("HOLD_SOURCE_IDENTITY_MISMATCH")
    if not set(wanted).issubset(live_names):
        return hold("HOLD_RUNTIME_MEMBERSHIP_MISMATCH")
    # Exactly the upstream intended single shared select parent.
    groups = config["proxy-groups"]
    if any(not isinstance(g, dict) or not isinstance(g.get("name"), str)
           or not isinstance(g.get("proxies"), list) for g in groups):
        return hold("HOLD_MALFORMED_GROUP")
    existing = [g["name"] for g in groups]
    if len(existing) != len(set(existing)) or len(set(actual) & set(existing)) > 0:
        return hold("HOLD_NAME_COLLISION")
    matched = [g for g in groups if g["name"] == PARENT]
    if len(matched) != 1 or matched[0].get("type") != "select":
        return hold("HOLD_PARENT_NOT_MANUAL")
    if len(matched[0]["proxies"]) != len(set(matched[0]["proxies"])):
        return hold("HOLD_PARENT_DUPLICATE")

    state, metrics, queue = updated_state(
        previous_manifest, current_manifest, previous_state,
        update_succeeded=True, runtime_loaded=True, now=now,
    )
    # Build complete SERVICE-specific and three-service intersection catalogs
    # first; no arbitrary 3-node / 58-node limit, dynamic ISO-2 regions.
    full_pools = {}
    for service in (SHARED_SERVICE, *SERVICES):
        full_pools[(service, "GLOBAL")] = qualified_pool(
            current_manifest, state, observations, live_names,
            service=service, region="GLOBAL", now=now,
        )
    verified_countries = sorted({
        item["country"]
        for service in (SHARED_SERVICE, *SERVICES)
        for item in full_pools[(service, "GLOBAL")]
    })
    for service in (SHARED_SERVICE, *SERVICES):
        for country in verified_countries:
            full_pools[(service, country)] = [
                item for item in full_pools[(service, "GLOBAL")]
                if item["country"] == country
            ]

    output = deepcopy(config)
    parent = next(g for g in output["proxy-groups"] if g["name"] == PARENT)
    produced = []
    active_labels = set(existing) | set(actual)
    all_selected = set()
    for service in (SHARED_SERVICE, *SERVICES):
        for country in ("GLOBAL", *verified_countries):
            pool = full_pools[(service, country)]
            if not pool:
                continue
            name = group_name(service, country)
            if name in active_labels:
                return hold(HOLD_NAME_CONFLICT)
            active_labels.add(name)
            leaves = [item["name"] for item in pool]
            if len(leaves) != len(set(leaves)):
                return hold("HOLD_AMBIGUOUS_QUALIFIED_POOL")
            for leaf in leaves:
                n = actual.get(leaf)
                if (not isinstance(n, dict)
                        or n.get("type") in (None, "select", "url-test", "fallback", "DIRECT", "REJECT")
                        or leaf in existing
                        or leaf in ("DIRECT", "REJECT", "GLOBAL", "COMPATIBLE")):
                    return hold("HOLD_NOT_A_DIRECT_LEAF")
            all_selected.update(leaves)
            # Single member is selectable, but not an automatic failover.
            group = {
                "name": name,
                "type": "fallback" if len(leaves) > 1 else "select",
                "proxies": leaves,
            }
            if len(leaves) > 1:
                group.update(url=HEALTH_URL, interval=300, timeout=4000, lazy=True)
            produced.append(group)
            if service == SHARED_SERVICE:
                parent["proxies"].append(name)
    output["proxy-groups"].extend(produced)

    public = {
        "decision": ("OFFLINE_CANDIDATE_ONLY"
                     if full_pools[(SHARED_SERVICE, "GLOBAL")]
                     else "OFFLINE_SERVICE_POOLS_ONLY_NO_SHARED_AI"),
        "all_sources_covered": True,  # ONLY within caller-verified inline-only snapshot
        "source_total": len(wanted),
        "source_added": metrics["added"],
        "source_removed": metrics["removed"],
        "source_replaced_same_name": metrics["replaced_same_name"],
        "retained_service_evidence": metrics["service_evidence_retained"],
        "pending_rechecks": len(queue),
        "qualified_group_count": len(produced),
        "verified_country_count": len(verified_countries),
        "qualified_leaf_count": len(all_selected),
        "shared_three_service_nodes": len(full_pools[(SHARED_SERVICE, "GLOBAL")]),
        "chatgpt_nodes": len(full_pools[("chatgpt", "GLOBAL")]),
        "gemini_nodes": len(full_pools[("gemini", "GLOBAL")]),
        "notebooklm_nodes": len(full_pools[("notebooklm", "GLOBAL")]),
        "extra_live_untrusted": len(live_names - set(wanted)),
        "live_apply": False, "switch": False, "non_ai_mutation": False,
    }
    return {
        "public": public,
        "private_candidate": output,
        "private_state": state,
        "private_probe_queue": queue,
    }


if __name__ == "__main__":
    raise SystemExit("Offline planner only. No router controller action or deployment.")
