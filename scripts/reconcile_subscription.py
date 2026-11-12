#!/usr/bin/env python3
"""Private, read-only subscription reconciliation; DO NOT auto-deploy or switch AI.

Called on a successful airport refresh (or manually), this detects changing
node membership and same-name connection changes independently of the count.
Manifests remain private (0600) and contain names + fingerprints, no plaintext
credentials. Console reports only counts, never names, IPs, URLs or hashes.

This is NOT an OpenClash update hook and will NOT install/schedule itself.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from subscription_snapshot import read_private_snapshot, validate_snapshot, snapshot_bytes, MAX_CONFIG_BYTES

ROOT = Path(__file__).resolve().parents[1]


def private_file(path: Path) -> Path:
    real=Path(path).expanduser().resolve()
    if real == ROOT or ROOT in real.parents:
        raise ValueError("private manifest and node source must stay outside public Git repo")
    return real


def build_manifest(config: dict, snapshot: dict) -> dict:
    validate_snapshot(snapshot)
    if not isinstance(config, dict) or not isinstance(config.get("proxies"), list):
        raise ValueError("active configuration has no proxies list")
    fingerprints={}
    for node in config["proxies"]:
        if not isinstance(node, dict) or not isinstance(node.get("name"), str) or not node["name"]:
            raise ValueError("invalid node entry")
        name=node["name"]
        if name in fingerprints:
            raise ValueError("ambiguous duplicate node names")
        # Includes endpoint, auth, TLS, transport, etc. Same name on a new
        # airport route is NOT permitted to reuse the previous service verdict.
        canonical=yaml.safe_dump(node, allow_unicode=True, sort_keys=True).encode("utf-8")
        fingerprints[name]=hashlib.sha256(canonical).hexdigest()
    return {
        "schema_version":1,
        "generated_at":datetime.now(timezone.utc).isoformat(),
        "subscription_snapshot":snapshot,
        "node_count":len(fingerprints),
        "node_fingerprints":fingerprints,
    }


def validate_manifest(manifest: dict) -> None:
    if not isinstance(manifest,dict) or manifest.get("schema_version") != 1:
        raise ValueError("invalid private manifest schema")
    validate_snapshot(manifest.get("subscription_snapshot"))
    nodes=manifest.get("node_fingerprints")
    if not isinstance(nodes,dict) or manifest.get("node_count") != len(nodes):
        raise ValueError("invalid private node count")
    if any(not isinstance(n,str) or not n or not isinstance(v,str) or len(v)!=64
           or any(c not in "0123456789abcdef" for c in v)
           for n,v in nodes.items()):
        raise ValueError("invalid private node identity")


def compare_manifests(previous: dict | None, current: dict) -> dict:
    validate_manifest(current)
    after=current["node_fingerprints"]
    if previous is None:
        return {"current":len(after),"added":len(after),"removed":0,
                "replaced_same_name":0,"unchanged":0,"source_changed":True,
                "audit_required":True}
    validate_manifest(previous)
    before=previous["node_fingerprints"]
    added=len(after.keys()-before.keys())
    removed=len(before.keys()-after.keys())
    modified=sum(before[name]!=after[name] for name in before.keys() & after.keys())
    unchanged=len(before.keys() & after.keys())-modified
    changed=previous["subscription_snapshot"]!=current["subscription_snapshot"]
    return {"current":len(after),"added":added,"removed":removed,
            "replaced_same_name":modified,"unchanged":unchanged,
            "source_changed":changed,"audit_required":changed or modified>0 or added>0 or removed>0}


def safe_create(path: Path, payload: str) -> None:
    if not path.parent.is_dir():
        raise ValueError("output must be an existing private directory")
    flags=os.O_CREAT|os.O_EXCL|os.O_WRONLY
    if hasattr(os, "O_NOFOLLOW"): flags|=os.O_NOFOLLOW
    fd=os.open(path,flags,0o600)
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        f.write(payload)


def main() -> int:
    parser=argparse.ArgumentParser(description="Private dynamic subscription reconciliation; no network writes")
    parser.add_argument("--node-config",required=True,type=Path)
    parser.add_argument("--previous-manifest",type=Path)
    parser.add_argument("--manifest-output",required=True,type=Path)
    args=parser.parse_args()
    try:
        source=private_file(args.node_config)
        destination=private_file(args.manifest_output)
        raw=source.read_bytes()
        if not 0<len(raw)<=MAX_CONFIG_BYTES:
            raise ValueError("private YAML exceeds size limit")
        config=yaml.safe_load(raw)
        # Fingerprint the EXACT bytes parsed above. Never hash a second file\n        # read to establish identity: a refresh could race in between.\n        manifest=build_manifest(config,snapshot_bytes(raw))
        prior=None
        if args.previous_manifest is not None:
            old=private_file(args.previous_manifest)
            prior=json.loads(old.read_text(encoding="utf-8"))
        summary=compare_manifests(prior,manifest)
        if manifest["subscription_snapshot"] != read_private_snapshot(source):
            raise ValueError("subscription refreshed during snapshot read")
        safe_create(destination,json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
        # Deliberately no names, endpoint, subscription URL, fingerprints.
        print("Subscription snapshot checked:",json.dumps(summary,sort_keys=True))
        print("Private manifest created; no live routing, subscription or AI group modified.")
        return 0
    except (OSError,ValueError,TypeError,KeyError,yaml.YAMLError,json.JSONDecodeError):
        print("Subscription reconciliation rejected; check private inputs (details withheld).",file=sys.stderr)
        return 2


if __name__=="__main__":
    raise SystemExit(main())
