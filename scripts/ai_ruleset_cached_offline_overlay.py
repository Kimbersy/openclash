#!/usr/bin/env python3
"""OFFLINE ONLY: private rule-cache overlay from synthetic caller inputs.

NOT for iStoreOS. Never loads the router or fetches provider data. Conversion
to local file providers is limited to a TEMPORARY parser test and does NOT
prove operational HTTP-provider update semantics. Explicit real-device
receipt: 20 HTTP provider cache paths exist, GEO_MODE_ENABLED=1; the latter
does not identify which GEO flag caused it. Unknown Geo dependencies HOLD.
"""
from __future__ import annotations
from copy import deepcopy
from pathlib import PurePosixPath

AI_PARENT = "🤖 AI"
GROUP = "__AI_NOTEBOOK_PROBE_ONLY__"
LISTENER = "ai-notebook-probe-only"
PORT = 17881
MAX_PROVIDERS = 2000
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 48 * 1024 * 1024


def _safe_provider_path(path: object) -> bool:
    if not isinstance(path, str) or not path or "\x00" in path:
        return False
    p = PurePosixPath(path)
    return not p.is_absolute() and ".." not in p.parts and len(p.parts) <= 12


def private_file_overlay(config: object, rule_cache_bytes: object) -> tuple[dict | None, dict]:
    """Pure in-memory planning: caller supplies cache bytes, no filesystem I/O."""
    def hold(code: str) -> tuple[None, dict]:
        return None, {"decision": code, "file_provider_conversions": 0,
                      "live_writes": False, "network_requests": False,
                      "installed": False, "business_verified": False}

    if not isinstance(config, dict) or not isinstance(rule_cache_bytes, dict):
        return hold("HOLD_INPUT_LAYOUT")
    providers = config.get("rule-providers")
    if not isinstance(providers, dict) or not providers or len(providers) > MAX_PROVIDERS:
        return hold("HOLD_PROVIDER_LAYOUT")
    if config.get("proxy-providers") not in (None, {}):
        return hold("HOLD_PROXY_SOURCE_LAYOUT")
    if config.get("geodata-mode") is True or config.get("geo-auto-update") is True or "geox-url" in config:
        return hold("HOLD_GEO_RESOURCE_NOT_MIRRORED")
    if any(k in config for k in ("script", "sub-rules", "external-ui-url")):
        return hold("HOLD_EXTERNAL_RESOURCE")
    proxies, groups = config.get("proxies"), config.get("proxy-groups")
    listeners, rules = config.get("listeners", []), config.get("rules")
    if (not isinstance(proxies, list) or not proxies or not isinstance(groups, list) or
            not isinstance(listeners, list) or not isinstance(rules, list) or
            not all(isinstance(x, str) for x in rules)):
        return hold("HOLD_CONFIG_LAYOUT")
    if any("GEOSITE," in r.upper() or "GEOIP," in r.upper() for r in rules):
        return hold("HOLD_GEO_RULE_NOT_MIRRORED")
    if any(isinstance(g, dict) and (g.get("use") or g.get("include-all"))
           for g in groups):
        return hold("HOLD_PROXY_SOURCE_LAYOUT")
    leaf = [p.get("name") for p in proxies if isinstance(p, dict)]
    gnames = [g.get("name") for g in groups if isinstance(g, dict)]
    if (len(leaf) != len(proxies) or len(gnames) != len(groups) or
            any(not isinstance(x, str) or not x for x in leaf + gnames) or
            len(set(leaf)) != len(leaf) or len(set(gnames)) != len(gnames) or
            set(leaf).intersection(gnames) or GROUP in leaf + gnames):
        return hold("HOLD_NAMES")
    if sum(g.get("name") == AI_PARENT and g.get("type") == "select" for g in groups) != 1:
        return hold("HOLD_AI_PARENT")
    if any(not isinstance(x, dict) or x.get("name") == LISTENER or x.get("port") == PORT
           for x in listeners):
        return hold("HOLD_LISTENER_COLLISION")
    for key in ("port", "mixed-port", "socks-port", "redir-port", "tproxy-port"):
        if config.get(key) == PORT:
            return hold("HOLD_PORT_COLLISION")
    if set(rule_cache_bytes) != set(providers) or any(not isinstance(name, str) for name in providers):
        return hold("HOLD_CACHE_IDENTITY_MISMATCH")

    total = 0
    for name, data in providers.items():
        if not isinstance(data, dict) or data.get("type") != "http":
            return hold("HOLD_UNSUPPORTED_PROVIDER_TYPE")
        if not _safe_provider_path(data.get("path")):
            return hold("HOLD_PROVIDER_PATH")
        if data.get("path-in-bundle") is not None:
            return hold("HOLD_PROVIDER_BUNDLE")
        fmt, behavior = data.get("format", "yaml"), data.get("behavior")
        if fmt not in ("yaml", "text", "mrs") or behavior not in ("domain", "ipcidr", "classical"):
            return hold("HOLD_PROVIDER_FORMAT")
        if fmt == "mrs" and behavior == "classical":
            return hold("HOLD_PROVIDER_FORMAT")
        if not isinstance(data.get("url"), str) or not data["url"].startswith("https://"):
            return hold("HOLD_PROVIDER_ORIGIN")
        cached = rule_cache_bytes[name]
        if not isinstance(cached, bytes) or not 0 < len(cached) <= MAX_FILE_BYTES:
            return hold("HOLD_CACHE_BYTES_UNVERIFIED")
        total += len(cached)
        if total > MAX_TOTAL_BYTES:
            return hold("HOLD_CACHE_BUDGET")

    out = deepcopy(config)
    cloned_files = {}
    for i, name in enumerate(providers):
        original = providers[name]
        dest = f"./test_rule_cache/cache_{i:04d}.{original.get('format', 'yaml')}"
        out["rule-providers"][name] = {
            "type": "file", "path": dest, "behavior": original["behavior"],
            "format": original.get("format", "yaml")
        }
        cloned_files[dest] = rule_cache_bytes[name]
    out["proxy-groups"].append({
        "name": GROUP, "type": "select", "proxies": ["REJECT", *leaf]
    })
    out.setdefault("listeners", []).append({
        "name": LISTENER, "type": "http", "listen": "127.0.0.1",
        "port": PORT, "proxy": GROUP
    })
    unchanged = set(config) - {"rule-providers", "proxy-groups", "listeners"}
    if any(out[k] != config[k] for k in unchanged):
        return hold("HOLD_UNEXPECTED_SOURCE_MUTATION")
    return {"config": out, "cache_files": cloned_files}, {
        "decision": "OFFLINE_PRIVATE_FILE_PROVIDER_SYNTAX_CANDIDATE",
        "file_provider_conversions": len(providers),
        "cache_total_bytes": total,
        "live_writes": False, "network_requests": False,
        "installed": False, "business_verified": False
    }
