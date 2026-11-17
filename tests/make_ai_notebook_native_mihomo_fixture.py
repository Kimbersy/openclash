#!/usr/bin/env python3
"""Synthetic fixture for OFFLINE native Mihomo parser (-t), not router config."""
import pathlib
import sys
import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from ai_notebook_one_core_probe_candidate import candidate_one_core_probe_listener

BASE = {
    "mixed-port": 7890,
    "allow-lan": False,
    "mode": "rule",
    "log-level": "silent",
    "proxies": [
        {"name": "TEST_0", "type": "http", "server": "example.invalid", "port": 8080},
        {"name": "TEST_1", "type": "http", "server": "example-two.invalid", "port": 8080},
    ],
    "proxy-groups": [
        {"name": "🤖 AI", "type": "select", "proxies": ["TEST_0", "TEST_1", "DIRECT"]},
        {"name": "🏰 Disney+", "type": "select", "proxies": ["TEST_0", "DIRECT"]},
    ],
    "rules": [
        "DOMAIN-SUFFIX,chatgpt.com,🤖 AI",
        "DOMAIN-SUFFIX,disneyplus.com,🏰 Disney+",
        "GEOIP,CN,DIRECT",
        "MATCH,🤖 AI",
    ],
}
out, status = candidate_one_core_probe_listener(BASE, source_identity_verified=True)
assert status["decision"] == "OFFLINE_ISOLATED_LISTENER_CANDIDATE_ONLY"
assert out["proxy-groups"][:-1] == BASE["proxy-groups"]
assert out["rules"] == BASE["rules"]
assert out["proxy-groups"][-1]["proxies"] == ["REJECT", "TEST_0", "TEST_1"]
assert out["listeners"] == [{
    "name": "ai-notebook-probe-only", "type": "http",
    "listen": "127.0.0.1", "port": 17881,
    "proxy": "__AI_NOTEBOOK_PROBE_ONLY__",
}]

# This output is synthetic. No real airport node is included. Mihomo -t
# checks grammar/structure; this is NOT an installed router-core proof.
path = pathlib.Path(sys.argv[1])
path.write_text(yaml.safe_dump(out, allow_unicode=True, sort_keys=False), encoding="utf-8")
print("SYNTHETIC_NATIVE_CONFIG_READY=YES LIVE_WRITES=NONE")
