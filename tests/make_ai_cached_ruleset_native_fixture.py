#!/usr/bin/env python3
"""Synthetic 20-provider private cache fixture for official Mihomo -t CI.

No real router data, no user URLs, no network calls. Never run on iStoreOS.
"""
from pathlib import Path
import sys
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from ai_ruleset_cached_offline_overlay import private_file_overlay

home = Path(sys.argv[1])
home.mkdir(parents=True, exist_ok=True)
rules = {}
files = {}
for i in range(20):
    name = f"TEST_RULE_{i:02d}"
    rules[name] = {
        "type": "http",
        "url": f"https://example.invalid/rule_{i:02d}.yaml",
        "path": f"./remote_rules/{i:02d}.yaml",
        "interval": 86400,
        "behavior": "classical",
        "format": "yaml",
    }
    files[name] = b"payload:\n  - 'DOMAIN-SUFFIX,static.example.invalid'\n"

source = {
    "mode": "rule", "allow-lan": False, "log-level": "silent",
    "mixed-port": 7890,
    "proxies": [{"name": "TEST_0", "type": "http",
                 "server": "192.0.2.1", "port": 8080}],
    "proxy-groups": [
        {"name": "🤖 AI", "type": "select", "proxies": ["TEST_0", "DIRECT"]},
        {"name": "Disney+", "type": "select", "proxies": ["DIRECT"]},
    ],
    "rule-providers": rules,
    "rules": [f"RULE-SET,TEST_RULE_{i:02d},🤖 AI" for i in range(20)] +
             ["DOMAIN-SUFFIX,disneyplus.com,Disney+", "MATCH,DIRECT"],
}
result, receipt = private_file_overlay(source, files)
assert receipt["decision"] == "OFFLINE_PRIVATE_FILE_PROVIDER_SYNTAX_CANDIDATE"
assert receipt["file_provider_conversions"] == 20
assert result["config"]["rules"] == source["rules"]
assert result["config"]["proxy-groups"][:-1] == source["proxy-groups"]
assert all(d["type"] == "http" for d in source["rule-providers"].values())
assert all(d["type"] == "file" for d in result["config"]["rule-providers"].values())
for rel, raw in result["cache_files"].items():
    target = home / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(raw)
    assert target.read_bytes() == raw
(home / "config.yaml").write_text(
    yaml.safe_dump(result["config"], allow_unicode=True, sort_keys=False),
    encoding="utf-8",
)
print("SYNTHETIC_20_RULE_CACHE_OVERLAY=CREATED NETWORK_REQUESTS=NONE REAL_SOURCE=NONE")
