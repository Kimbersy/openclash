#!/usr/bin/env python3
"""OFFLINE Mihomo native one-core, one-loopback-port NotebookLM probe candidate.

Only CONFIG GENERATION, no live sockets, Core restart, API writes, subscription
downloads or proxy selection.  The dedicated listener routes directly to its
private select group; the existing '🤖 AI' parent and all non-AI groups, rules,
proxies, DNS and credentials remain byte-for-byte equal as Python values.

Mihomo docs: listeners[].proxy routes listener traffic directly to the named
proxy or group. Do not install this merely because code/CI passes: check actual
installed core version, loopback bind, free port, operator-controlled selector
changes, restore/rollback and current source fingerprints independently.
"""
from __future__ import annotations

from copy import deepcopy
from typing import Any

LISTENER_NAME = "ai-notebook-probe-only"
GROUP_NAME = "__AI_NOTEBOOK_PROBE_ONLY__"
LISTEN = "127.0.0.1"
PORT = 17881
AI_PARENT = "🤖 AI"
RESERVED = frozenset(("DIRECT", "REJECT", "GLOBAL", "COMPATIBLE", "PASS"))


def candidate_one_core_probe_listener(config: Any, *, source_identity_verified: bool = False) -> tuple[dict, dict]:
    """Return (detached candidate or unchanged copy, ANONYMOUS verdict).

    source_identity_verified=True is a CALLER ASSERTION, not a credential or
    runtime-loading attestation. This generator cannot authorize installation.
    """
    if not isinstance(config, dict) or type(source_identity_verified) is not bool:
        raise ValueError("invalid private config/flag")
    original = deepcopy(config)

    def hold(reason: str) -> tuple[dict, dict]:
        return deepcopy(original), {
            "decision": reason, "actual_device_validated": False,
            "live_writes": False, "controller_put": False, "switch": False,
        }

    if not source_identity_verified:
        return hold("HOLD_SOURCE_IDENTITY_UNVERIFIED")
    proxies, groups, listeners = (config.get("proxies"), config.get("proxy-groups"),
                                  config.get("listeners", []))
    if (not isinstance(proxies, list) or not isinstance(groups, list)
            or not isinstance(listeners, list)):
        return hold("HOLD_UNSUPPORTED_CONFIG_LAYOUT")
    if config.get("proxy-providers") not in (None, {}):
        return hold("HOLD_PROVIDER_LOADED_PROOF_MISSING")
    if len(proxies) == 0:
        return hold("HOLD_NO_INLINE_LEAVES")
    leaf_names = []
    for node in proxies:
        if (not isinstance(node, dict) or not isinstance(node.get("name"), str)
                or not node["name"] or node["name"] in RESERVED
                or node.get("type") not in (
                    "ss", "socks5", "http", "vmess", "vless", "trojan", "hysteria2",
                    "hysteria", "tuic", "wireguard", "snell", "ssh", "mieru",
                )):
            return hold("HOLD_UNVERIFIED_LEAF_TYPE")
        leaf_names.append(node["name"])
    if len(leaf_names) != len(set(leaf_names)):
        return hold("HOLD_DUPLICATE_NODE_NAME")
    group_names = []
    for group in groups:
        if (not isinstance(group, dict) or not isinstance(group.get("name"), str)
                or not isinstance(group.get("proxies"), list)):
            return hold("HOLD_GROUP_LAYOUT")
        group_names.append(group["name"])
    if (len(group_names) != len(set(group_names))
            or set(group_names).intersection(leaf_names)
            or GROUP_NAME in group_names or GROUP_NAME in leaf_names):
        return hold("HOLD_GROUP_NAME_CONFLICT")
    parents = [g for g in groups if g["name"] == AI_PARENT]
    if len(parents) != 1 or parents[0]["type"] != "select":
        return hold("HOLD_ORIGINAL_AI_PARENT_CHANGED")
    existing_names = []
    used_ports = set()
    for listener in listeners:
        if not isinstance(listener, dict) or not isinstance(listener.get("name"), str):
            return hold("HOLD_LISTENER_LAYOUT")
        existing_names.append(listener["name"])
        port = listener.get("port")
        if isinstance(port, int) and type(port) is int:
            used_ports.add(port)
        elif isinstance(port, str) and port.isdigit():
            used_ports.add(int(port))
        elif port is not None:
            return hold("HOLD_UNVERIFIED_LISTENER_PORT")
    if (len(set(existing_names)) != len(existing_names)
            or LISTENER_NAME in existing_names):
        return hold("HOLD_LISTENER_NAME_CONFLICT")
    for key in ("port", "socks-port", "mixed-port", "redir-port", "tproxy-port"):
        value = config.get(key)
        if value is None:
            continue
        if type(value) is int:
            used_ports.add(value)
        elif isinstance(value, str) and value.isdigit():
            used_ports.add(int(value))
        else:
            return hold("HOLD_UNVERIFIED_CORE_PORT")
    if PORT in used_ports:
        return hold("HOLD_PORT_COLLISION")
    # No new polling timers. A private SELECT list containing all leaves does
    # NOT use fallback or background URL tests, so it consumes no test cycles.
    # REJECT is the default (first) member to avoid accidentally using an exit.
    generated = deepcopy(config)
    generated["proxy-groups"].append({
        "name": GROUP_NAME, "type": "select", "proxies": ["REJECT", *leaf_names],
    })
    generated.setdefault("listeners", []).append({
        "name": LISTENER_NAME, "type": "http", "listen": LISTEN,
        "port": PORT, "proxy": GROUP_NAME,
    })
    # No change to AI parent members/rules; only the dedicated loopback
    # listener can ever consume the probe group.
    return generated, {
        "decision": "OFFLINE_ISOLATED_LISTENER_CANDIDATE_ONLY",
        "isolated_listener_count": 1,
        "probe_leaf_count": len(leaf_names),
        "loopback_only": True, "starts_disabled": True,
        "actual_device_validated": False,
        "live_writes": False, "controller_put": False, "switch": False,
    }


if __name__ == "__main__":
    raise SystemExit("Offline config library; do not execute or install on a router.")
