#!/usr/bin/env python3
"""Conservative per-node egress audit. This is a private runner component.

The caller must start one isolated localhost HTTP CONNECT proxy per node.
No airport subscription or credentials are read or fetched by this script.
No GitHub state or active Clash configuration is changed.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import ipaddress
import json
import os
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from subscription_snapshot import assert_current_snapshot, validate_snapshot

from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener

COUNTRIES = {
    "TW": r"台湾|台灣|臺灣|台北|臺北|🇹🇼|\b(?:TW|TWN|Taiwan|Taipei)\b",
    "HK": r"香港|🇭🇰|\b(?:HK|HKG|Hong\s*Kong)\b",
    "JP": r"日本|東京|东京|🇯🇵|\b(?:JP|JPN|Japan|Tokyo)\b",
    "SG": r"新加坡|狮城|獅城|🇸🇬|\b(?:SG|SGP|Singapore)\b",
    "US": r"美国|美國|洛杉矶|洛杉磯|🇺🇸|\b(?:US|USA|United\s*States)\b",
    "KR": r"韩国|韓國|首尔|首爾|🇰🇷|\b(?:KR|KOR|Korea|Seoul)\b",
    "DE": r"德国|德國|🇩🇪|\b(?:DE|DEU|Germany)\b",
}
LABEL_PATTERNS = {k: re.compile(v, re.IGNORECASE) for k, v in COUNTRIES.items()}
SOURCES = (
    ("ipinfo", "https://ipinfo.io/json", "country"),
    ("ipapi", "https://ipapi.co/json/", "country_code"),
)


def advertised_country(name: str) -> str | None:
    found = [cc for cc, pattern in LABEL_PATTERNS.items() if pattern.search(name)]
    return found[0] if len(found) == 1 else None


def validate_local_proxy(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "::1", "localhost"}:
        raise ValueError("only loopback HTTP proxies are allowed")
    if parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment:
        raise ValueError("proxy URL may not have credentials, path, or query")
    if not parsed.port:
        raise ValueError("proxy must have an explicit port")
    return value


def probe(proxy_url: str, timeout: int = 8) -> tuple[list[dict], list[str]]:
    """Observe internet-facing IP via the specified node, not the node server IP."""
    opener = build_opener(ProxyHandler({"http": proxy_url, "https": proxy_url}))
    results, errors = [], []
    for provider, endpoint, country_field in SOURCES:
        try:
            request = Request(endpoint, headers={"Accept": "application/json", "User-Agent": "egress-audit/0.2"})
            with opener.open(request, timeout=timeout) as response:
                if response.status != 200:
                    raise ValueError("unexpected HTTP status")
                raw = response.read(16385)
            if len(raw) > 16384:
                raise ValueError("response too large")
            payload = json.loads(raw)
            ip = str(ipaddress.ip_address(str(payload["ip"])))
            cc = str(payload[country_field]).upper()
            if not re.fullmatch(r"[A-Z]{2}", cc):
                raise ValueError("invalid ISO country code")
            results.append({"source": provider, "ip": ip, "country": cc})
        except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
            errors.append(provider + ":" + type(exc).__name__)
    return results, errors


def classify(name: str, observations: list[dict], errors: list[str]) -> dict:
    """Name/real egress are independent. A country mismatch is NOT unusable.

    Platform suitability (ChatGPT, NotebookLM, Gemini, etc.) must be evaluated
    separately. A geolocation probe alone cannot certify service accessibility.
    """
    claim = advertised_country(name)
    sources = {r.get("source") for r in observations}
    ips = {r.get("ip") for r in observations}
    countries = {r.get("country") for r in observations}
    record = {
        "name": name, "claimed_country": claim, "observed_country": None,
        "observed_ips": sorted(ip for ip in ips if ip),
        "evidence_sources": sorted(src for src in sources if src),
        "egress_verified": False,
        "status": "unknown", "probe_errors": errors,
        "service_availability": {},  # no platform claims without separate checks
    }
    if sources != {"ipinfo", "ipapi"}:
        record["reason"] = "insufficient_sources"
    elif len(ips) != 1 or len(countries) != 1:
        record["status"] = "inconsistent"
        record["reason"] = "geolocation_or_egress_conflict"
    else:
        actual = next(iter(countries))
        record["observed_country"] = actual
        record["egress_verified"] = True
        if claim is None:
            record["reason"] = "missing_or_ambiguous_country_in_name"
        else:
            record["status"] = "match" if actual == claim else "mismatch"
            record["reason"] = "two_source_agreement"
    return record

def exact_name_regex(names: list[str]) -> str:
    # Escape literal proxy names for compatibility with Mihomo / Shadowrocket regex.
    if not names:
        return "(?!)"
    return "^(?:" + "|".join(re.escape(n) for n in sorted(set(names))) + ")$"


def audit(inventory: dict, timeout: int = 8) -> dict:
    if inventory.get("schema_version") != 1 or not isinstance(inventory.get("nodes"), list):
        raise ValueError("schema_version 1 with nodes list required")
    validate_snapshot(inventory.get("subscription_snapshot"))
    count = inventory.get("source_node_count")
    if type(count) is not int or count < len(inventory["nodes"]) or count < 1:
        raise ValueError("invalid dynamic subscription node count")
    if len(inventory["nodes"]) > 500:
        raise ValueError("maximum 500 nodes")
    records, seen_names, seen_proxies = [], set(), set()
    for entry in inventory["nodes"]:
        if not isinstance(entry, dict):
            raise ValueError("invalid node entry")
        name = entry.get("name")
        if not isinstance(name, str) or not (1 <= len(name) <= 150) or any(c in name for c in "\r\n"):
            raise ValueError("invalid node name")
        url = validate_local_proxy(entry["proxy_url"])
        if name in seen_names or url in seen_proxies:
            raise ValueError("duplicate node name or proxy port")
        seen_names.add(name)
        seen_proxies.add(url)
        observations, errors = probe(url, timeout)
        records.append(classify(name, observations, errors))
    matched_label = defaultdict(list)
    observed_exit = defaultdict(list)
    for record in records:
        # Comparison to a node label is only informational. Real exit country,
        # when independently verified, determines geolocation grouping.
        if record["status"] == "match":
            matched_label[record["claimed_country"]].append(record["name"])
        if record["egress_verified"]:
            observed_exit[record["observed_country"]].append(record["name"])
    return {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "meaning": "two-source real egress country; NOT AI platform eligibility or stable connection proof",
        "nodes": records,
        "subscription_snapshot": inventory["subscription_snapshot"],
        "source_node_count": inventory["source_node_count"],
        # Retain legacy for existing report consumers, but new candidates must
        # rely on observed_exit_name_filters instead of name-agreement only.
        "verified_name_filters": {country: exact_name_regex(matched_label[country]) for country in COUNTRIES},
        "observed_exit_name_filters": {
            country: exact_name_regex(names) for country, names in sorted(observed_exit.items())
        },
    }


def secure_write_json(path: Path, data: dict) -> None:
    """Limit reports containing exit IP and node labels to the local OS user."""
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(path, flags, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit actual per-node egress through private loopback proxies")
    parser.add_argument("--inventory", type=Path, required=True, help="PRIVATE file containing node/loopback proxy mapping")
    parser.add_argument("--report", type=Path, required=True, help="PRIVATE output file; never commit")
    parser.add_argument("--node-config", type=Path, required=True,
                        help="PRIVATE active subscription YAML used when inventory was prepared")
    parser.add_argument("--timeout", type=int, default=8)
    args = parser.parse_args()
    try:
        if not (1 <= args.timeout <= 30):
            raise ValueError("timeout must be 1-30 seconds")
        inventory = json.loads(args.inventory.read_text(encoding="utf-8"))
        # Refuse to probe or certify if an airport refresh has already changed
        # the node configuration since the isolated listeners were prepared.
        assert_current_snapshot(inventory.get("subscription_snapshot"), args.node_config)
        result = audit(inventory, args.timeout)
        assert_current_snapshot(inventory["subscription_snapshot"], args.node_config)
        secure_write_json(args.report, result)
        counts = defaultdict(int)
        for record in result["nodes"]:
            counts[record["status"]] += 1
        print("Audit complete:", dict(counts))
        print("Private report saved; production subscription unchanged.")
        return 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("Audit failed: " + type(exc).__name__, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
