#!/usr/bin/env python3
"""Router P0: PRIVATE/OFFLINE AI-only Mihomo fallback candidate, not installer.

Reuse existing full-node fingerprints, genuine service business receipts,
observed exit country and bounded health from ai_service_stability_dry_run.
The generator intentionally does not install or write configuration, perform
proxy tests, send controller PUTs, or enable automation. In particular:
- no changing any rules, proxy definitions, providers, or non-AI groups;
- add only a flat fallback group whose members are 2-3 DIRECT LEAF proxies;
- append it as a MANUAL option of the existing '🤖 AI' select parent;
- fallback makes basic network-health decisions, not AI business verdicts;
- on stale evidence or any mismatch, leave the supplied config unchanged.
The two Boolean preconditions are NOT attestations themselves. The caller must
validate independent source and runtime proof before passing them as true.
"""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
from hashlib import sha256
from typing import Any

import yaml
from ai_service_stability_dry_run import qualified_pool
from reconcile_subscription import validate_manifest

PARENT = "🤖 AI"
AUTO = "🛡️AI·路由器自动主备"
HEALTH_URL = "https://cp.cloudflare.com/generate_204"
MAX_BACKUPS = 3


def fingerprint(node: dict[str, Any]) -> str:
    """Same exact full-node identity canonicalization as reconcile_subscription."""
    return sha256(yaml.safe_dump(
        node, allow_unicode=True, sort_keys=True
    ).encode("utf-8")).hexdigest()


def build_router_p0_candidate(
    config: dict,
    manifest: dict,
    state: dict,
    observations: dict,
    live_names: set[str],
    *,
    region: str,
    now: datetime,
    source_coverage_verified: bool = False,
    runtime_loaded_verified: bool = False,
) -> tuple[dict, dict]:
    """Returns (detached config candidate, anonymous status).

    When blocked, returns a deep copy of the unmodified original config;
    never publishes names, fingerprints or credentials in status. Any source
    and generated output are PRIVATE. This does not run on iStoreOS.
    """
    if not isinstance(config, dict) or not isinstance(region, str) or not isinstance(now, datetime) or now.tzinfo is None:
        raise ValueError("invalid private input")
    if type(source_coverage_verified) is not bool or type(runtime_loaded_verified) is not bool:
        raise ValueError("invalid attestation precondition")
    output = deepcopy(config)

    def hold(status: str, count: int = 0) -> tuple[dict, dict]:
        return output, {"status": status, "eligible": count,
                        "selected": 0, "writes": False, "switch": False}

    if not source_coverage_verified or not runtime_loaded_verified:
        return hold("HOLD_INDEPENDENT_SOURCE_OR_RUNTIME_PROOF")
    validate_manifest(manifest)
    wanted = manifest["node_fingerprints"]
    if (not isinstance(config.get("proxies"), list) or not isinstance(config.get("proxy-groups"), list)
            or config.get("proxy-providers") not in (None, {})):
        return hold("HOLD_UNSUPPORTED_SOURCE_LAYOUT")
    if not isinstance(live_names, set) or not all(isinstance(name, str) for name in live_names):
        return hold("HOLD_INVALID_LIVE_CATALOG")

    actual = {}
    for node in config["proxies"]:
        if (not isinstance(node, dict) or not isinstance(node.get("name"), str)
                or not node["name"] or node["name"] in actual):
            return hold("HOLD_AMBIGUOUS_PROXY_IDENTITY")
        actual[node["name"]] = node
    if set(wanted) != set(actual):
        return hold("HOLD_SOURCE_CATALOG_MISMATCH")
    if any(fingerprint(actual[name]) != fp for name, fp in wanted.items()):
        return hold("HOLD_FULL_NODE_FINGERPRINT_MISMATCH")
    if not set(wanted).issubset(live_names):
        return hold("HOLD_MISSING_RUNTIME_NAMES")

    groups = config["proxy-groups"]
    if any(not isinstance(g, dict) or not isinstance(g.get("name"), str) for g in groups):
        return hold("HOLD_INVALID_GROUPS")
    names = [g["name"] for g in groups]
    if len(names) != len(set(names)) or AUTO in names or AUTO in actual:
        return hold("HOLD_GROUP_NAME_COLLISION")
    parents = [g for g in groups if g["name"] == PARENT]
    if (len(parents) != 1 or parents[0].get("type") != "select"
            or not isinstance(parents[0].get("proxies"), list)):
        return hold("HOLD_AI_PARENT_NOT_MANUAL_SELECT")
    if len(parents[0]["proxies"]) != len(set(parents[0]["proxies"])):
        return hold("HOLD_AMBIGUOUS_AI_PARENT")
    if AUTO in parents[0]["proxies"]:
        return hold("HOLD_GROUP_NAME_COLLISION")

    if not isinstance(state, dict) or not isinstance(observations, dict):
        return hold("HOLD_NO_BUSINESS_EVIDENCE")
    pool = qualified_pool(manifest, state, observations, live_names,
                          service="shared_all_services", region=region,
                          now=now.astimezone(timezone.utc))
    if len(pool) < 2:
        return hold("HOLD_NO_BUSINESS_VERIFIED_MAIN_AND_BACKUP", len(pool))
    # Native fallback health check must target direct leaf names; no indirect
    # shared-country / other-business group, DIRECT, REJECT or unknown extras.
    selected = []
    for item in pool[:MAX_BACKUPS]:
        node = actual[item["name"]]
        if (node.get("type") in (None, "select", "url-test", "fallback", "DIRECT", "REJECT")
                or item["name"] in ("DIRECT", "REJECT", "COMPATIBLE", "GLOBAL")):
            return hold("HOLD_NOT_A_DIRECT_LEAF", len(pool))
        selected.append(item["name"])

    # Non-AI groups and the exact original parent members are not reordered.
    out_groups = output["proxy-groups"]
    parent = next(group for group in out_groups if group["name"] == PARENT)
    parent["proxies"].append(AUTO)  # append, never select automatically
    out_groups.append({
        "name": AUTO,
        "type": "fallback",
        "proxies": selected,
        "url": HEALTH_URL,
        "interval": 300,
        "timeout": 4000,
        "lazy": True,
    })
    return output, {
        "status": "OFFLINE_AI_FALLBACK_CANDIDATE_ONLY",
        "eligible": len(pool), "selected": len(selected),
        "writes": False, "switch": False,
        "activation": "REQUIRES_EXPLICIT_PARENT_SELECTION_AND_ROUTER_ACCEPTANCE",
    }


if __name__ == "__main__":
    raise SystemExit("Pure offline library only; never install or activate on a router.")
