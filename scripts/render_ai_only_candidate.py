#!/usr/bin/env python3
"""AI-only *offline* candidate renderer for the existing shared converter.

Accepts only the intersection of three independently BUSINESS-qualified,
fresh, identity-pinned service pools from a trusted private upstream.
Never publishes or switches any running client. Never edits main files.
The generated groups are MANUAL selects; runtime failover is separate.
"""
from __future__ import annotations

import re
from typing import Any

from render_verified_candidate import literal_filter

AI_PARENT = "🤖 AI"
ALL = "🛡️AI·三平台合格"
PREFIX = "🛡️AI·地区"
SERVICES = ("chatgpt", "gemini", "notebooklm")
GROUP_PREFIX = "custom_proxy_group="
RULE_PREFIX = "ruleset="
COUNTRY = re.compile(r"[A-Z]{2}\Z")
SAFE_NAME = re.compile(r"[^,`\\\r\n]+\Z")


def validate_verified_intersection(
    pools: dict,
    *,
    source_coverage_verified: bool,
    active_runtime_confirmed: bool,
    platform_business_verified: bool,
) -> dict[str, list[str]]:
    """Fail closed unless upstream evidence has been independently verified.

    The boolean gates are NOT evidence. Callers must validate private manifest,
    full fingerprints, timestamps, business receipts, and current runtime first.
    Pools from AiRegionalPools.build alone are NOT sufficient to pass these gates.
    """
    if not all(x is True for x in
               (source_coverage_verified, active_runtime_confirmed, platform_business_verified)):
        raise ValueError("current, complete, platform-business-verified source required")
    if not isinstance(pools, dict):
        raise ValueError("invalid private AI pools")
    per = pools.get("per_service")
    all_services = pools.get("all_services")
    if (not isinstance(per, dict) or set(per) != set(SERVICES)
            or not isinstance(all_services, dict)):
        raise ValueError("missing independently verified service pools")
    for svc in SERVICES:
        if not isinstance(per[svc], dict):
            raise ValueError("invalid per-service region catalog")
    result = {}
    seen = set()
    for cc, names in sorted(all_services.items()):
        if not isinstance(cc, str) or not COUNTRY.fullmatch(cc):
            raise ValueError("invalid observed country")
        if not isinstance(names, list) or not names:
            raise ValueError("empty verified region")
        clean = []
        for name in names:
            if (not isinstance(name, str) or not name or len(name) > 150
                    or SAFE_NAME.fullmatch(name) is None or name in seen):
                raise ValueError("unsafe or duplicate node name")
            if not all(name in per[svc].get(cc, []) for svc in SERVICES):
                raise ValueError("three-platform qualification incomplete")
            clean.append(name)
            seen.add(name)
        result[cc] = clean
    return result


def build_ai_only_candidate(
    base_ini: str,
    pools: dict,
    *,
    source_coverage_verified: bool = False,
    active_runtime_confirmed: bool = False,
    platform_business_verified: bool = False,
) -> tuple[str, dict]:
    """Return a private candidate INI, plus an anonymous inspection summary.

    The base's rule lines and every non-AI group are *exactly* preserved.
    Never add service-specific automatic routes to shared Google login domains.
    Never auto-select an unverified backup or change an existing selection.
    """
    if not isinstance(base_ini, str):
        raise ValueError("missing base ini")
    qualified = validate_verified_intersection(
        pools,
        source_coverage_verified=source_coverage_verified,
        active_runtime_confirmed=active_runtime_confirmed,
        platform_business_verified=platform_business_verified,
    )
    lines = base_ini.splitlines(keepends=True)
    indices = [i for i, line in enumerate(lines)
               if line.startswith(GROUP_PREFIX + AI_PARENT + "`select`")]
    if len(indices) != 1:
        raise ValueError("AI parent select must appear exactly once")
    if any(line.startswith(GROUP_PREFIX + ALL + "`")
           or line.startswith(GROUP_PREFIX + PREFIX)
           for line in lines):
        raise ValueError("candidate has existing AI qualified groups")
    if not qualified:
        return base_ini, {"status": "NO_BUSINESS_VERIFIED_POOL", "countries": 0, "nodes": 0}

    original_groups = [line for line in lines if line.startswith(GROUP_PREFIX)]
    original_rules = [line for line in lines if line.startswith(RULE_PREFIX)]
    added_names = [ALL] + [PREFIX + cc for cc in qualified]
    existing_names = {line[len(GROUP_PREFIX):].split("`", 1)[0] for line in original_groups}
    if any(name in existing_names for name in added_names):
        raise ValueError("name collision with original group")

    # Keep the original parent line prefix and all members in the same order.
    index = indices[0]
    line = lines[index]
    ending = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
    updated = line[:-len(ending)] if ending else line
    lines[index] = updated + "".join("`[]" + g for g in added_names) + ending

    # The only new groups have select behavior: no misleading url-test/fallback
    # pretending gstatic 204 means ChatGPT+Gemini+NotebookLM usable.
    members = [n for names in qualified.values() for n in names]
    suffix = [
        "; PRIVATE AI-ONLY VERIFIED CANDIDATE. DO NOT PUBLISH BEFORE TRI-CLIENT ACCEPTANCE.\n",
        GROUP_PREFIX + ALL + "`select`" + literal_filter(members) + "\n",
    ]
    for country, names in qualified.items():
        suffix.append(GROUP_PREFIX + PREFIX + country + "`select`" + literal_filter(names) + "\n")
    candidate = "".join(lines) + ("" if base_ini.endswith("\n") else "\n") + "".join(suffix)

    changed = candidate.splitlines()
    out_rules = [line for line in changed if line.startswith(RULE_PREFIX)]
    out_groups = [line for line in changed if line.startswith(GROUP_PREFIX)]
    if out_rules != original_rules or out_groups[:len(original_groups)] != (
        original_groups[:index] + [lines[index]] + original_groups[index+1:]
    ):
        raise ValueError("non-AI routing or group order was changed")
    return candidate, {"status": "PRIVATE_MANUAL_CANDIDATE_ONLY",
                       "countries": len(qualified), "nodes": len(members)}


if __name__ == "__main__":
    raise SystemExit("Library only: no live writes, subscriptions, API switches or deployments.")
