#!/usr/bin/env python3
"""Build private candidate configs for Mihomo and Shadowrocket from a fresh egress audit.

No existing subscription, source .ini, or generated/ files are modified.
Use only a trusted local audit report. Never commit the private outputs.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
REGIONS = {
    "TW": "🇹🇼台湾",
    "HK": "🇭🇰香港",
    "JP": "🇯🇵日本",
    "SG": "🇸🇬新加坡",
    "US": "🇺🇸美国",
    "KR": "🇰🇷韩国",
    "DE": "🇩🇪德国",
}
AI_ELIGIBLE_GROUP_OPTIONS = ("TW", "JP", "SG", "US")
# Optional AI-only Taiwan fallback. Slower probes than existing 180s fallback.
# Opt-in only; cannot preserve a long-running AI connection during switchover.
AI_STABLE_TW_GROUP = "🛡️AI 稳态🇹🇼台湾"
AI_STABLE_TW_URL = "https://www.gstatic.com/generate_204"
AI_STABLE_TW_INTERVAL = 600
AI_STABLE_TW_TIMEOUT = 10


def parse_utc(value: str) -> datetime:
    stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        raise ValueError("audit time must include a UTC offset")
    return stamp.astimezone(timezone.utc)


def verified_names(report: dict, now: datetime | None = None, ttl_hours: int = 6) -> dict[str, list[str]]:
    if report.get("schema_version") != 1 or not isinstance(report.get("nodes"), list):
        raise ValueError("audit schema invalid")
    if not (1 <= ttl_hours <= 48):
        raise ValueError("TTL must be 1-48 hours")
    now = now or datetime.now(timezone.utc)
    stamp = parse_utc(report["generated_at"])
    if stamp > now + timedelta(minutes=2) or now - stamp > timedelta(hours=ttl_hours):
        raise ValueError("audit has expired or is in the future")
    selected = defaultdict(list)
    seen = set()
    for rec in report["nodes"]:
        if not isinstance(rec, dict) or "name" not in rec:
            raise ValueError("invalid audit entry")
        name = rec["name"]
        if not isinstance(name, str) or not name or len(name) > 150 or any(x in name for x in ("\n", "\r", "`", ",", "\\")):
            raise ValueError("unsupported node name for shared converter")
        if name in seen:
            raise ValueError("duplicate node name in report")
        seen.add(name)
        if rec.get("status") != "match":
            continue
        cc = rec.get("claimed_country")
        if cc not in REGIONS or rec.get("observed_country") != cc:
            raise ValueError("match record has inconsistent country")
        if set(rec.get("evidence_sources", [])) != {"ipinfo", "ipapi"}:
            raise ValueError("match record lacks two evidence sources")
        ips = rec.get("observed_ips")
        if not isinstance(ips, list) or len(ips) != 1:
            raise ValueError("match record lacks a unique egress IP")
        selected[cc].append(name)
    return {cc: sorted(names) for cc, names in selected.items() if names}


def literal_filter(names: list[str]) -> str:
    """Anchor the full name; outer noncapturing group survives existing INI converter cleanup.

    Existing generate_android.clean_include_regex strips leading ^ and trailing $.
    A normal ^name$ filter would become a substring match. The outer (?:...) keeps
    the anchors intact, and has syntax accepted by Mihomo RE2 and Shadowrocket regex.
    """
    if not names:
        raise ValueError("verified filter cannot be empty")
    specials = re.compile(r"([\\.^$|?*+()\[\]{}])")
    escaped = [specials.sub(r"\\\1", name) for name in sorted(set(names))]
    pattern = "(?:^(?:" + "|".join(escaped) + ")$)"
    if len(pattern) > 4000:
        raise ValueError("candidate country group too large for safe portable filtering")
    return pattern


def build_candidate_ini(source: str, names_by_country: dict[str, list[str]]) -> str:
    if not names_by_country:
        raise ValueError("no validated nodes, refuse candidate generation")
    lines = source.splitlines()
    target_index = next((i for i, line in enumerate(lines)
                         if line.startswith("custom_proxy_group=🤖 AI`select`")), None)
    if target_index is None:
        raise ValueError("expected existing AI select policy")
    if any("🧭核验" in line for line in lines):
        raise ValueError("candidate already has verified groups")
    extra = []
    for cc in REGIONS:
        if not names_by_country.get(cc):
            continue
        label = "🧭核验" + REGIONS[cc]
        extra.append("custom_proxy_group=" + label + "`select`" + literal_filter(names_by_country[cc]))
    # Optional, source/provider-order fallback among verified TW exits only.
    # Requires >=2 good nodes; on recovery fallback may switch back and disrupt
    # a live AI stream. This mode is not enabled by default.
    tw_names = names_by_country.get("TW", [])
    if len(tw_names) >= 2:
        extra.append(
            "custom_proxy_group=" + AI_STABLE_TW_GROUP + "`fallback`"
            + literal_filter(tw_names)
            + "`" + AI_STABLE_TW_URL
            + "`" + str(AI_STABLE_TW_INTERVAL) + "," + str(AI_STABLE_TW_TIMEOUT)
        )
    # New choices only, appended *after* original AI choices. Existing saved/default
    # AI selection and all existing groups remain unchanged.
    ai_refs = "".join("`[]🧭核验" + REGIONS[cc]
                      for cc in AI_ELIGIBLE_GROUP_OPTIONS if names_by_country.get(cc))
    if len(tw_names) >= 2:
        ai_refs += "`[]" + AI_STABLE_TW_GROUP
    lines[target_index] += ai_refs
    lines.extend(["", "; ===== PRIVATE VERIFIED-EGRESS CANDIDATE: NOT FOR PUBLIC COMMIT =====", *extra])
    return "\n".join(lines) + "\n"


def generate_both(candidate_ini: str) -> tuple[str, str]:
    # Import existing battle-tested generators; do not duplicate their policy semantics.
    sys.path.insert(0, str(ROOT / "scripts"))
    import generate_android
    import generate_shadowrocket

    source = Path(candidate_ini)
    arules, agroups = generate_android.parse_ini(source)
    generate_android.validate_config(arules, agroups)
    srules, sgroups = generate_shadowrocket.parse_ini(source)
    if len(agroups) != len(sgroups) or len(arules) != len(srules):
        raise ValueError("Android/Shadowrocket parser disagreement")
    android = generate_android.generate_android(arules, agroups)
    shadowrocket = generate_shadowrocket.generate_shadowrocket(srules, sgroups)
    if "__AIRPORT_URL__" not in android:
        raise ValueError("Android provider placeholder missing")
    return android, shadowrocket


def secure_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate PRIVATE cross-device configs using verified exit IP evidence")
    parser.add_argument("--report", type=Path, required=True, help="private result from audit_egress.py")
    parser.add_argument("--source-ini", type=Path, default=ROOT / "Clash-Li.ini")
    parser.add_argument("--output-dir", type=Path, required=True, help="PRIVATE directory outside public git repo")
    parser.add_argument("--ttl-hours", type=int, default=6)
    args = parser.parse_args()
    try:
        # Fail closed. Never allow a public-repo output destination by default.
        output = args.output_dir.resolve()
        if output == ROOT or ROOT in output.parents:
            raise ValueError("output directory must be outside the public repository")
        report = json.loads(args.report.read_text(encoding="utf-8"))
        verified = verified_names(report, ttl_hours=args.ttl_hours)
        source = args.source_ini.read_text(encoding="utf-8")
        candidate = build_candidate_ini(source, verified)
        output.mkdir(parents=True, exist_ok=True, mode=0o700)
        output.chmod(0o700)
        ini_path = output / "Clash-Li.verified-candidate.ini"
        secure_write(ini_path, candidate)
        android, shadowrocket = generate_both(str(ini_path))
        secure_write(output / "Clash-Meta-Android.verified-candidate.yaml", android)
        secure_write(output / "Shadowrocket.verified-candidate.conf", shadowrocket)
        print("Private candidate generated for both clients. Counts:",
              {cc: len(names) for cc, names in verified.items()})
        print("Existing main branch, AI selection and installed clients remain unchanged.")
        return 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, ImportError) as exc:
        print("Candidate generation failed:", type(exc).__name__, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
