#!/usr/bin/env python3
"""Fail-closed PRIVATE airport-subscription snapshot checks.

An airport can add, remove, rename or silently change a same-named proxy on
every refresh. A six-hour egress TTL alone is not sufficient. This module
pins the actual private subscription YAML bytes at preparation time and
requires the identical bytes at audit and candidate-generation time.

Hashes are PRIVATE audit metadata, not public node identifiers. Never print
the YAML, password, subscription URL, node names or snapshot digest in CI.
A formatting-only change also invalidates old results (intentional safe default).
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import re

MAX_CONFIG_BYTES = 12_000_000


def snapshot_bytes(raw: bytes) -> dict:
    if not isinstance(raw, bytes) or len(raw) == 0 or len(raw) > MAX_CONFIG_BYTES:
        raise ValueError("private subscription snapshot has invalid size")
    return {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "byte_count": len(raw),
    }


def read_private_snapshot(path: Path) -> dict:
    p = Path(path).expanduser().resolve()
    size = p.stat().st_size
    if not 0 < size <= MAX_CONFIG_BYTES:
        raise ValueError("private subscription config has invalid size")
    return snapshot_bytes(p.read_bytes())


def validate_snapshot(metadata: object) -> None:
    if not isinstance(metadata, dict):
        raise ValueError("missing subscription snapshot metadata")
    if set(metadata) != {"sha256", "byte_count"}:
        raise ValueError("unrecognized subscription snapshot metadata")
    if not isinstance(metadata["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", metadata["sha256"]):
        raise ValueError("invalid subscription snapshot hash")
    n = metadata["byte_count"]
    if type(n) is not int or not 0 < n <= MAX_CONFIG_BYTES:
        raise ValueError("invalid subscription snapshot length")


def assert_current_snapshot(metadata: object, path: Path) -> None:
    validate_snapshot(metadata)
    if read_private_snapshot(path) != metadata:
        raise ValueError("airport subscription changed; refresh node inventory and re-audit before generating candidate")
