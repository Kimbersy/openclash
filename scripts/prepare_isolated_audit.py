#!/usr/bin/env python3
"""Prepare isolated localhost HTTP listeners for real per-node egress checks.

Input is an existing PRIVATE Mihomo-compatible proxies YAML. The selected
node credentials never leave this computer, and this script does not run or
modify any live Clash/OpenClash instance. It emits an inventory compatible
with audit_egress.py and a separate, minimal Mihomo config.

Requires PyYAML (pip install PyYAML==6.0.2).
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import socket
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from subscription_snapshot import snapshot_bytes, assert_current_snapshot

try:
    import yaml
except ImportError:  # Make a missing dependency an explicit safe failure.
    yaml = None

ROOT = Path(__file__).resolve().parents[1]
BUILTIN_NAMES = {"DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"}


def private_path(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if resolved == ROOT or ROOT in resolved.parents:
        raise ValueError("private input/output must not be inside the public repository")
    return resolved


def validate_selected(names: object) -> list[str]:
    if not isinstance(names, list) or not 1 <= len(names) <= 32:
        raise ValueError("select 1-32 exact proxy node names")
    if any(not isinstance(n, str) or not 1 <= len(n) <= 150
           or any(x in n for x in "\r\n") or n.upper() in BUILTIN_NAMES
           for n in names):
        raise ValueError("invalid proxy name in selection")
    if len(set(names)) != len(names):
        raise ValueError("duplicate selected node name")
    return names


def reserve_check(ports: list[int]) -> None:
    """Preflight only; the separate Mihomo process binds the ports later."""
    for port in ports:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 0)
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                raise ValueError("some requested local listener ports are occupied") from None


def build_isolated(node_config: dict, selected: list[str], start_port: int) -> tuple[dict, dict]:
    if not isinstance(node_config, dict) or not isinstance(node_config.get("proxies"), list):
        raise ValueError("input must contain a top-level proxies list")
    nodes = {}
    for entry in node_config["proxies"]:
        if not isinstance(entry, dict):
            raise ValueError("invalid proxy entry")
        name = entry.get("name")
        if not isinstance(name, str) or not name:
            raise ValueError("proxy without a name")
        if name in nodes:
            raise ValueError("duplicate proxy names in node config")
        if not isinstance(entry.get("type"), str) or entry["type"].lower() in {
            "direct", "reject", "reject-drop", "pass", "compatible"
        }:
            raise ValueError("builtin/non-proxy types cannot be audited")
        nodes[name] = entry
    if any(name not in nodes for name in selected):
        raise ValueError("at least one selected node is absent from the private provider file")
    if not 10000 <= start_port <= 65535 - len(selected) + 1:
        raise ValueError("listener ports must be between 10000 and 65535")
    ports = list(range(start_port, start_port + len(selected)))
    listeners = [
        {"name": f"audit-node-{i + 1}", "type": "http", "listen": "127.0.0.1",
         "port": port, "proxy": name, "users": []}
        for i, (name, port) in enumerate(zip(selected, ports))
    ]
    # Explicit per-listener proxy bypasses routing rules. MATCH,REJECT is a
    # fail-closed safeguard if a listener proxy setting is not honored.
    config = {
        "allow-lan": False,
        "mode": "rule",
        "log-level": "warning",
        "ipv6": True,
        "proxies": [nodes[name] for name in selected],
        "listeners": listeners,
        "rules": ["MATCH,REJECT"],
    }
    inventory = {
        "schema_version": 1,
        "nodes": [
            {"name": name, "proxy_url": f"http://127.0.0.1:{port}"}
            for name, port in zip(selected, ports)
        ],
    }
    return config, inventory


def secure_write(path: Path, data: str) -> None:
    # Creation-only; do not accidentally overwrite existing private output.
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(data)


def main() -> int:
    p = argparse.ArgumentParser(description="Prepare private isolated Mihomo egress audit, no live changes")
    p.add_argument("--node-config", type=Path, required=True,
                   help="PRIVATE Mihomo YAML with top-level proxies; never put in public Git")
    p.add_argument("--names-json", type=Path, required=True,
                   help="PRIVATE JSON array of exact selected node names")
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument("--start-port", type=int, default=17801)
    args = p.parse_args()
    try:
        if yaml is None:
            raise ValueError("PyYAML dependency missing; install PyYAML==6.0.2")
        source = private_path(args.node_config)
        names_file = private_path(args.names_json)
        dest = private_path(args.output_dir)
        if dest.exists():
            raise ValueError("use a fresh private output directory; refusing to overwrite")
        names = validate_selected(json.loads(names_file.read_text(encoding="utf-8")))
        # Read exactly once so the analyzed node list and private snapshot
        # are from the same subscription refresh. No node data is logged.
        raw_config = source.read_bytes()
        config, inventory = build_isolated(
            yaml.safe_load(raw_config), names, args.start_port
        )
        inventory["subscription_snapshot"] = snapshot_bytes(raw_config)
        inventory["source_node_count"] = len(yaml.safe_load(raw_config)["proxies"])
        reserve_check([listener["port"] for listener in config["listeners"]])
        # If an OpenClash subscription refresh raced with preparation, do not
        # create an apparently verified inventory from an obsolete source.
        assert_current_snapshot(inventory["subscription_snapshot"], source)
        dest.mkdir(parents=True, mode=0o700)
        dest.chmod(0o700)
        secure_write(dest / "isolated-mihomo.yaml",
                     yaml.safe_dump(config, allow_unicode=True, sort_keys=False))
        secure_write(dest / "egress-inventory.json",
                     json.dumps(inventory, ensure_ascii=False, indent=2) + "\n")
        assert_current_snapshot(inventory["subscription_snapshot"], source)
        print("Prepared", len(names), "isolated loopback listeners in a private directory.")
        print("No live OpenClash configuration changed; no node credentials printed.")
        print("Validate isolated-mihomo.yaml with a separately installed Mihomo binary before use.")
        return 0
    except (OSError, ValueError, json.JSONDecodeError, yaml.YAMLError if yaml else ValueError):
        print("Private audit setup rejected; check local input and permissions (details hidden).",
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
